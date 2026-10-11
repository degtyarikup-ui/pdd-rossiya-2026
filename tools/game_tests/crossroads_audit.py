import json
import time
import math
import sys
from selenium import webdriver
from selenium.webdriver.firefox.options import Options

def main():
    print("==================================================")
    print("   Starting Comprehensive Crossroads 3D Audit     ")
    print("==================================================")

    with open('/tmp/crossroads_scenarios.json', 'r', encoding='utf-8') as f:
        scenarios = json.load(f)
    print(f"Loaded {len(scenarios)} certified scenarios.")

    opts = Options()
    opts.add_argument('--headless')
    opts.set_preference("dom.webnotifications.enabled", False)
    opts.set_preference("media.volume_scale", "0.0")

    driver = webdriver.Firefox(options=opts)
    driver.set_window_size(1080, 1920)

    try:
        url = "http://127.0.0.1:8080/app/assets/assets/game/crossroads.html"
        print(f"Connecting to {url}...")
        driver.get(url)
        time.sleep(1.5)

        # Inject hooks
        driver.execute_script("""
            window.smokeEvents = [];
            window.consoleErrors = [];
            const origErr = console.error;
            console.error = function(...args) {
                window.consoleErrors.push(args.map(a => String(a)).join(' '));
                origErr.apply(console, args);
            };
            window.FlutterChannel = {
                postMessage: function(raw) {
                    try {
                        window.smokeEvents.push(JSON.parse(raw));
                    } catch(e) {
                        window.smokeEvents.push(raw);
                    }
                }
            };
            window.PDD_BRIDGE = {
                send: function(payload) {
                    window.smokeEvents.push(payload);
                }
            };
        """)

        # Wait for engine readiness
        ready = False
        for _ in range(30):
            has_pdd = driver.execute_script("return typeof window._pddCrossroads !== 'undefined';")
            if has_pdd:
                ready = True
                break
            time.sleep(0.2)
        assert ready, "window._pddCrossroads not initialized"
        print("✓ Three.js engine and window._pddCrossroads ready.")

        # Test A: Basic Exports
        print("\n--- Test A: Exports & Global API ---")
        exports = driver.execute_script("""
            return {
                loadScenarioData: typeof window.loadScenarioData,
                selectVehicle: typeof window.selectVehicle,
                resetCurrentScenario: typeof window.resetCurrentScenario,
                setViewInset: typeof window.setViewInset,
                setZoom: typeof window.setZoom,
                resetCamera: typeof window.resetCamera
            };
        """)
        for k, v in exports.items():
            assert v == 'function', f"Export {k} is not a function: {v}"
            print(f"  ✓ {k}: function")

        # Test B: Verify all 17 Scenarios scene construction
        print(f"\n--- Test B: Scene Construction for All {len(scenarios)} Scenarios ---")
        geometry_counts = []
        locations = set()
        for idx, scenario in enumerate(scenarios, start=1):
            sc_id = scenario['id']
            driver.execute_script("""
                window.smokeEvents = [];
                window.loadScenarioData(arguments[0]);
                window.setViewInset(90, 220);
                window.setZoom(1);
            """, scenario)
            time.sleep(0.15)

            # Check actors mesh count
            actor_mesh_count = driver.execute_script("""
                return window._pddCrossroads.vehiclesGroup.children.length;
            """)
            assert actor_mesh_count == len(scenario['actors']), (
                f"[{sc_id}] Vehicles count mismatch: {actor_mesh_count} vs {len(scenario['actors'])}"
            )

            # Inspect scene details
            scene_info = driver.execute_script("""
                const { scene, scenarioGroup, signsGroup, renderer } = window._pddCrossroads;
                let spots = 0, rain = 0, rails = 0;
                scene.traverse(o => {
                    if (o.isSpotLight) spots++;
                    if (o.isLineSegments || o.isPoints) rain++;
                });
                scenarioGroup.children.forEach(o => {
                    const p = o.geometry && o.geometry.parameters;
                    if (p && Math.min(p.width, p.depth) === 0.08) rails++;
                });
                const lawn = scenarioGroup.children.some(o => o.material && o.material.userData && o.material.userData.pddKind === 'grass');
                const signs = signsGroup.children.map(g => ({
                    x: g.position.x, z: g.position.z, ry: g.rotation.y
                }));
                return {
                    spots, rain, rails, lawn,
                    signsCount: signs.length,
                    signs: signs,
                    geometries: renderer.info.memory.geometries,
                    location: window._pddCrossroads.location()
                };
            """)

            # Assertions
            assert scene_info['spots'] == 0, f"Headlight spots found in {sc_id}"
            assert scene_info['rain'] == 0, f"Rain found in {sc_id}"
            
            # Rails check
            trams = [a for a in scenario['actors'] if a['type'] == 'tram']
            axes = set('ns' if a['side'] in ['north', 'south'] else 'ew' for a in trams)
            assert scene_info['rails'] == len(axes) * 2, (
                f"[{sc_id}] Rails count {scene_info['rails']} expected {len(axes)*2}"
            )

            # Closed side lawn check
            if scenario.get('closedSide'):
                assert scene_info['lawn'] is True, f"[{sc_id}] Closed arm must have grass lawn"

            # Signs count & direction
            expected_signs = len(scenario.get('signs') or [])
            assert scene_info['signsCount'] == expected_signs, (
                f"[{sc_id}] Signs count {scene_info['signsCount']} vs expected {expected_signs}"
            )
            for s in scene_info['signs']:
                nx = math.sin(s['ry'])
                nz = math.cos(s['ry'])
                assert nx * s['x'] + nz * s['z'] > 0, f"[{sc_id}] Sign does not face approach: {s}"

            locations.add(scene_info['location'])
            geometry_counts.append(scene_info['geometries'])
            print(f"  ✓ [{idx}/{len(scenarios)}] {sc_id}: {actor_mesh_count} cars, {expected_signs} signs, {len(axes)*2} rails, valid")

        assert len(locations) >= 3, f"Expected varied scenery locations, got {locations}"
        print(f"✓ Location variety verified: {locations}")

        # Test C: Correct Order Playthrough for All 17 Scenarios
        print(f"\n--- Test C: Step-by-step Correct Playthrough (All 17 Scenarios) ---")
        for sc in scenarios:
            sc_id = sc['id']
            actors = sorted(sc['actors'], key=lambda a: a['order'])
            driver.execute_script("window.smokeEvents = []; window.loadScenarioData(arguments[0]);", sc)
            time.sleep(0.1)

            step_count = 0
            for actor in actors:
                step_count += 1
                driver.execute_script(f"window.selectVehicle('{actor['id']}');")

                # Wait for step_correct event
                step_ok = False
                for _ in range(30):
                    time.sleep(0.05)
                    events = driver.execute_script("return window.smokeEvents;")
                    step_events = [e for e in events if e.get('type') == 'step_correct']
                    if len(step_events) >= step_count:
                        step_ok = True
                        break
                assert step_ok, f"[{sc_id}] step_correct not emitted for {actor['id']}"

                # Wait for vehicle to finish drive
                for _ in range(60):
                    time.sleep(0.05)
                    done = driver.execute_script(f"""
                        const mesh = window._pddCrossroads.vehiclesGroup.children.find(c => c.userData.actorId === '{actor['id']}');
                        return mesh && !mesh.visible;
                    """)
                    if done:
                        break

            # Wait for crossroad_complete event
            complete = False
            for _ in range(30):
                time.sleep(0.1)
                events = driver.execute_script("return window.smokeEvents;")
                if any(e.get('type') == 'crossroad_complete' for e in events):
                    complete = True
                    break
            assert complete, f"[{sc_id}] crossroad_complete event was not emitted!"
            assert not any(e.get('type') == 'collision' for e in events), f"[{sc_id}] Unexpected collision event!"
            print(f"  ✓ [{sc_id}] Completed successfully ({len(actors)} vehicles)")

        # Test D: Incorrect Choice Collision Verification
        print(f"\n--- Test D: Incorrect Choice Collision Verification ---")
        for sc in scenarios:
            sc_id = sc['id']
            actors = sorted(sc['actors'], key=lambda a: a['order'])
            if len(actors) < 2:
                continue

            driver.execute_script("window.smokeEvents = []; window.loadScenarioData(arguments[0]);", sc)
            time.sleep(0.1)

            # Pick wrong vehicle
            wrong = actors[-1]
            driver.execute_script(f"window.selectVehicle('{wrong['id']}');")

            # Wait for collision animation to finish and emit event
            collision = None
            for _ in range(40):
                time.sleep(0.05)
                events = driver.execute_script("return window.smokeEvents;")
                collision = next((e for e in events if e.get('type') == 'collision'), None)
                if collision:
                    break

            assert collision is not None, f"[{sc_id}] No collision emitted on wrong vehicle selection"
            assert collision.get('chosenId') == wrong['id']
            assert collision.get('priorityId') == actors[0]['id']
            assert len(collision.get('reason', '')) > 0, f"Empty reason in {sc_id}"
            assert len(collision.get('pddArticle', '')) > 0, f"Empty pddArticle in {sc_id}"

            # Verify taps blocked during resolution
            before_ev = len(driver.execute_script("return window.smokeEvents;"))
            driver.execute_script(f"window.selectVehicle('{actors[0]['id']}');")
            after_ev = len(driver.execute_script("return window.smokeEvents;"))
            assert before_ev == after_ev, f"[{sc_id}] Selection must be blocked during collision resolution"

            # Reset scenario
            driver.execute_script("window.resetCurrentScenario();")
            time.sleep(0.1)
            restored_count = driver.execute_script("return window._pddCrossroads.vehiclesGroup.children.length;")
            assert restored_count == len(actors), f"[{sc_id}] Vehicles count mismatch after reset"
            print(f"  ✓ [{sc_id}] Collision validated: {collision['pddArticle']} -> Reset verified")

        # Test E: Screen Tap / Pin Raycasting with PointerEvents
        print(f"\n--- Test E: Physical Tap on Badge Pin (PointerEvent) ---")
        sc0 = scenarios[0]
        actors0 = sorted(sc0['actors'], key=lambda a: a['order'])
        driver.execute_script("window.smokeEvents = []; window.loadScenarioData(arguments[0]);", sc0)
        time.sleep(0.2)

        first_actor = actors0[0]
        pin_coords = driver.execute_script(f"""
            const mesh = window._pddCrossroads.vehiclesGroup.children.find(c => c.userData.actorId === '{first_actor['id']}');
            const v = mesh.userData.badge.userData.sprite.getWorldPosition(new THREE.Vector3()).project(window._pddCrossroads.camera);
            const r = window._pddCrossroads.renderer.domElement.getBoundingClientRect();
            return {{
                x: Math.round((v.x + 1) / 2 * r.width),
                y: Math.round((1 - v.y) / 2 * r.height)
            }};
        """)
        print(f"  Target pin coords for {first_actor['id']}: {pin_coords}")

        driver.execute_script(f"""
            const el = window._pddCrossroads.renderer.domElement;
            el.dispatchEvent(new PointerEvent('pointerdown', {{
                pointerId: 1,
                clientX: {pin_coords['x']},
                clientY: {pin_coords['y']},
                bubbles: true
            }}));
            el.dispatchEvent(new PointerEvent('pointerup', {{
                pointerId: 1,
                clientX: {pin_coords['x']},
                clientY: {pin_coords['y']},
                bubbles: true
            }}));
        """)
        time.sleep(0.3)
        events = driver.execute_script("return window.smokeEvents;")
        tapped = any(e.get('type') == 'step_correct' and e.get('actorId') == first_actor['id'] for e in events)
        assert tapped, f"PointerEvent click on pin did not trigger step_correct! Events: {events}"
        print(f"  ✓ Physical click on 3D pin successfully dispatched vehicle: {first_actor['id']}")

        # Test F: Rapid Double Tap & Dynamic Collision (п. 13.8)
        print(f"\n--- Test F: Rapid Double Tap & Conflict Detection (п. 13.8 ПДД РФ) ---")
        conflict_sc = next(s for s in scenarios if s['id'] == 'cross_main_turns_left')
        c_actors = sorted(conflict_sc['actors'], key=lambda a: a['order'])
        driver.execute_script("window.smokeEvents = []; window.loadScenarioData(arguments[0]);", conflict_sc)
        time.sleep(0.1)

        # Dispatch 1, then immediately dispatch 2 after 80ms
        driver.execute_script(f"window.selectVehicle('{c_actors[0]['id']}');")
        time.sleep(0.08)
        driver.execute_script(f"window.selectVehicle('{c_actors[1]['id']}');")

        dyn_collision = None
        for _ in range(40):
            time.sleep(0.05)
            events = driver.execute_script("return window.smokeEvents;")
            dyn_collision = next((e for e in events if e.get('type') == 'collision'), None)
            if dyn_collision:
                break

        assert dyn_collision is not None, f"Dynamic collision was not triggered on intersecting paths! Events: {events}"
        assert '13.8' in dyn_collision.get('pddArticle', ''), f"Expected article 13.8, got {dyn_collision.get('pddArticle')}"
        print(f"  ✓ Dynamic collision detected: article={dyn_collision.get('pddArticle')}, reason='{dyn_collision.get('reason')}'")

        # Test G: Console Errors Audit
        print("\n--- Test G: JavaScript Console Errors Audit ---")
        console_errs = driver.execute_script("return window.consoleErrors;")
        for e in console_errs:
            print("  [ERROR]", e)
        assert len(console_errs) == 0, f"Detected {len(console_errs)} console errors!"
        print("✓ Zero console errors across all tests.")

        print("\n==================================================")
        print("   ALL AUDIT CHECKS PASSED PERFECTLY (0 ERRORS)   ")
        print("==================================================")

    finally:
        driver.quit()

if __name__ == '__main__':
    main()
