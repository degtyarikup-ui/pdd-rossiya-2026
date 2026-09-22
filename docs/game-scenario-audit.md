# RU game scenario audit

Scope (first batch): the first 60 SITUATIONS in assets/game/game.js (tickets 1–20), matched by ticket number and
one-based question number to assets/countries/ru/questions/questions_ab.json.
All source titles, explanations, answer options and correct indexes matched
during the read-only audit. All 59 referenced image paths exist and were viewed
in contact sheets; selected tram/turn scenes were additionally inspected at
original resolution. ticket_19_15 has no source image. This is repository fidelity,
not a claim about current law or a rendered-game visual acceptance test.

## Result

36 reviewed entries, 24 explicitly excluded. Reviewed maneuver coverage:
14 straight, 13 left, 7 right, 2 uturn. The scenario metadata is consumed by
the game engine; exclusions remain explicit rather than using guessed routes.

The expanded contract admits 8.13 plates, red-plus-green-arrow signals, flashing
yellow, amber beacons on trucks, and NPC uturns. Eighteen additional scenes are
enabled using individually viewed source images. Controllers, roundabouts,
observer questions, unspecified/multiple-choice maneuvers, and unsupported
staged/concurrent motion remain excluded. 9_15 also has a source inconsistency.

## Overrides API

Load scenario-routes.js before selecting scenes. It defines
window.PDD_SCENARIO_ROUTES, keyed by the exact situation id. No runtime heuristic,
source parsing, or inference from question text is used.

Each entry has:
- maneuver: straight, left, right or uturn for supported routes. Excluded entries
  retain a source-explicit maneuver where possible; null means no unique route.
- yieldTo: actor IDs in the replacement actorsConfig. For excluded entries the
  empty list is inert and MUST NOT be interpreted as an audited no-yield result.
- reviewed: only strict true permits selection.
- overrides: complete replacements for actorsConfig, signs and trafficLights.
- reason: present on every excluded entry.

Example parent integration (not implemented here):

```js
const routes = window.PDD_SCENARIO_ROUTES;
const pool = SITUATIONS.filter(s => routes?.[s.id]?.reviewed === true);
if (!pool.length) throw new Error('No reviewed game scenarios');
const original = pool[situationIndex % pool.length];
const spec = routes[original.id];
const situation = { ...original, ...structuredClone(spec.overrides) };
// Pass situation to the scene builder, and spec to the route resolver.
```

Do not merge actor arrays by index, concatenate signs, preserve old lights when
the override is null, or fall back to excluded scenes. Clone data before mutation.
Old type and legend fields are not authoritative route data: derive actor labels
from replacement actorsConfig so deleted placeholder cars do not remain in the
legend. Do not let the original type recreate a removed light.

All reviewed actor types and sides use the declared renderer vocabulary.
All targetAction values are straight, turn_left, turn_right or uturn. Pedestrians use
straight, but their type selects a crossing of the indicated destination-road
crosswalk, not a vehicle's forward trajectory. One pedestrian actor represents
the source pedestrian group.

Actors in 3_15, 8_15, 15_14 and 16_13 use explicit position and rotationY to
separate a tram and a car approaching together. These are existing placement fields, in the
scene factory's pre-mirroring coordinates: [x, y, centerZ-relative z], yaw in
radians. 15_14/16_13 are opposite/turn_left; 3_15 uses parallel west approaches,
8_15 parallel east approaches. The coordinates are schematic layout
choices, not surveyed measurements from the source image. Route curves must
preserve separation; two actors must not spawn at the same default position.

4_13 requires the parent-promised special-vehicle presentation:
actorsConfig[npc_special].beacon = blue and siren = true. Show active flashing
blue light AND audible/visible siren indication; the vehicle's body color alone
does not establish the question's priority condition. Disable this scene if
that capability is not delivered.

yieldTo expresses who must be allowed to pass, not a general legal total order.
Reviewed actor arrays put yielded actors first, in the intended conservative
animation order. 1_14 specifically requires B before A. 10_14 and 14_14 allow
simultaneous non-conflicting passage in the source; sequential passage is a
conservative animation choice and must not be presented as a legal requirement.
After the player in 19_14, the car must pass before the motorcycle.

18_14 deliberately selects the source's permitted wait-first solution: surrender
initial priority, let the car turn right, then complete the uturn. The alternative
enter-first/yield-during-turn solution is also valid; this module does not model it.

7_13 remains excluded because its correct answer explicitly requires crossing
the stop line before stopping to yield. Merely fixing its light and actor while
using a pre-entry yield phase would still demonstrate the wrong answer.
8_14 similarly needs actors to pause mid-maneuver rather than fully clear first.

## Schematic fidelity boundaries

The repaired scenes restore relevant actor identities, approaches, maneuvers,
priority signs and light state. They do not reproduce all buildings, parked or
distant traffic, roadside signs without priority effects, road widths, tram
track topology, medians, or the original viewpoint. For example 9_14 omits the
dead-end information sign; it does not grant priority. Straight opposing tram
paths and turning tram rails still require visual QA in the parent renderer.
No rendered gameplay/collision verification was performed by this data-only task.

Amber beacons are explicitly retained on trucks in 5_15, 17_14 and 18_15.
They do not grant emergency priority. The actor's normal color is separate from
the beacon color. All enabled actors have an explicit name and color; paired
trams have A/B badges and different colors, and the two trucks in 17_14 have
distinct names, badges and colors. Rebuild actor legends from these values;
derive the player label from maneuver, with the existing player color.

## Directional plates and expanded signal contract

Only signs facing the player are supplied. mainRoad lists the two THICK branches
of 8.13 in SOURCE driver-view coordinates: south = player approach, north =
opposite, east = driver's right, west = driver's left. Do not mirror these strings
when mirroring Three.js placement coordinates. A 2.4 approach generally is NOT
one of the thick branches: south is deliberately absent in 16_15, 18_13 and
20_15. Do not force south into every mainRoad array.

| Enabled situations | Player sign | 8.13 thick branches |
| --- | --- | --- |
| 1_15, 2_13, 3_15, 5_15, 7_15, 10_15 | 2.1 | south, west |
| 8_15, 12_15, 15_15 | 2.1 | south, east |
| 16_15 | 2.4 | west, east |
| 18_13 | 2.4 | north, east |
| 20_15 | 2.4 | west, north |

The diagonal right branch drawn in 10_15, 15_15 and 16_15 is normalized to east
in the supported four-approach model, not north. Its physical angle is schematic.
2_13 and 18_13 keep the source signs even though their green light takes priority.
No priority signs from other approaches are invented.

trafficLights {state: 'red', arrow: 'right'} means red main light AND illuminated
green right section (11_13, 17_13); arrow: 'straight' is the equivalent straight
section (19_13). Never turn the main light green while resolving these scenes.
{state: 'flashing_yellow'} in 11_15 and 12_15 means an unregulated intersection,
so the supplied priority signs remain operative. 11_13 uses targetAction: 'uturn'
for the car approaching from the driver's right.

## Source conflicts and motion exclusions

9_15 reuses the exact image of 1_15 (dd7e958840da9ddd1c102a65d8d5c03f):
main road south-west, bus on west, car on north. Its explanation instead calls
the bus secondary and places the car before it, contrary to that image and
1_15's explanation. The player's empty yield set agrees, but the NPC order does
not. Keep reviewed:false pending a repository-source correction; neither the
image nor the explanatory text was edited.

13_15's plate can now be rendered (2.4, mainRoad north-east), and the truck is
opposite/turn_left. It remains excluded because the correct answer distinguishes
respecting priority from waiting for a non-conflicting vehicle to clear. It needs
conflict-aware simultaneous left turns, not just a new sign. 7_13 and 8_14 retain
their inside-intersection/staged yielding exclusions.

Conservative serialization does not make a mandatory legal order where the
source permits concurrency. Keep the documented source order for 1_14, 7_15,
8_15, 17_14 and 20_15; arrays put actors in that order. In 3_15, car and B can
pass together after the player. In 16_15, the right-turning car may pass before
the opposing left-turning bus; both precede the player. Curved tram rails should
follow each actor route; all such scenes still need parent-renderer visual QA.

## Complete mapping

| Situation | reviewed | maneuver | yieldTo | Repair or exclusion reason |
| --- | --- | --- | --- | --- |
| `ticket_1_13` | true | right | `["cyclist","pedestrian"]` | Right turn; cyclist continues alongside player; pedestrian group crosses right destination road. |
| `ticket_1_14` | true | straight | `["tram_b","tram_a"]` | B crosses from left first; A turns left from opposite next; then player straight. |
| `ticket_1_15` | true | left | `[]` | 8.13 south-west; bus left/right turn, car opposite/straight; player first. |
| `ticket_2_13` | true | left | `["npc_bus","pedestrian"]` | Green with inactive 2.1 + 8.13 south-west; yield to opposite bus and left-destination pedestrians. |
| `ticket_2_14` | false | unresolved | not executable | Question offers both left and right; no unique player maneuver. Source truck from left replaces opposite placeholder car. |
| `ticket_2_15` | false | straight | not executable | Motorway entry/merge and sign 5.1 require different road geometry, not an ordinary crossroad. |
| `ticket_3_13` | true | straight | `[]` | Remove invented clearing car; green light makes STOP inactive. |
| `ticket_3_14` | true | right | `[]` | Opposite car turns left; motorcycle approaches right; player right first. |
| `ticket_3_15` | true | left | `["tram_a"]` | 8.13 south-west; A and car from left in separate lanes, B from right; yield only to A. |
| `ticket_4_13` | true | straight | `["npc_special"]` | Special crosses left with blue beacon AND siren; opposite truck turns left after player. |
| `ticket_4_14` | false | right | not executable | Requires approach crossing followed by destination-road crossing; available crosswalk sides model only destination crossings. Remove invented green light. |
| `ticket_4_15` | true | uturn | `["npc_car"]` | Restore secondary-road truck right; yield to opposite car, then uturn. |
| `ticket_5_13` | false | uturn | not executable | Requires traffic controller pose and orientation; car from left turns right. A green light is not an equivalent source depiction. |
| `ticket_5_14` | true | straight | `["tram_1"]` | Tram right/straight, car left/straight; yield only to tram. |
| `ticket_5_15` | true | left | `[]` | 8.13 south-west; opposite car then right-side amber-beacon truck after player. |
| `ticket_6_13` | false | left | not executable | Requires white tram signal, green light and same-direction tram-track lane entry before left turn. |
| `ticket_6_14` | true | left | `["cyclist","pedestrian"]` | Replace car/red light with opposite cyclist and left-destination pedestrian group. |
| `ticket_6_15` | false | unresolved | not executable | Conditional blue beacon plus siren question; no fixed maneuver or unconditional yield set. Source police vehicle absent. |
| `ticket_7_13` | false | left | not executable | Requires moving beyond stop line before yielding inside intersection; flat pre-maneuver yield phase cannot reproduce correct answer. Car opposite/straight; green light. |
| `ticket_7_14` | false | unresolved | not executable | Left/right alternatives, downstream congestion and green light; no single selected turn or queue model. |
| `ticket_7_15` | true | straight | `[]` | 8.13 south-west; restore motorcycle left/straight, truck opposite/left turn and car right/left turn. |
| `ticket_8_13` | false | unresolved | not executable | Observer question about car and motorcycle violating 4.1.1; no player maneuver. Green light, not red. |
| `ticket_8_14` | false | straight | not executable | Requires staged car left turn/pause, player passage, motorcycle passage, car completion; whole-actor yielding cannot implement the source sequence. Remove 2.4. |
| `ticket_8_15` | true | left | `["tram_b","npc_car"]` | 8.13 south-east; B and car from right in separate lanes, A left; B then car before player. |
| `ticket_9_13` | false | unresolved | not executable | Left/right alternatives with downstream queue and green light; straight/uturn not supported answers. |
| `ticket_9_14` | true | straight | `["npc_truck"]` | Replace car/red light with truck from right; unregulated. |
| `ticket_9_15` | false | left | not executable | Requires 8.13 and bus left/car opposite; player on main road, not facing 2.4. | | Source conflict: same image as 1_15 shows main road south-west and bus left, but 9_15 explanation calls bus secondary/last and car second. Player yield set is empty either way; NPC priority sequence cannot be reconciled without a source correction.
| `ticket_10_13` | false | unresolved | not executable | Requires red-yellow to green transition, adjacent truck occlusion and checking possible clearing actors; no fixed maneuver/yield set. |
| `ticket_10_14` | true | straight | `["tram_1","npc_truck"]` | Restore truck right alongside tram left; yield to both. |
| `ticket_10_15` | true | left | `[]` | 8.13 south-west; car left/right turn, bus right/left turn; player first. |
| `ticket_11_13` | true | right | `["npc_car"]` | Red plus green right arrow; car from right makes uturn before player right turn. |
| `ticket_11_14` | false | unresolved | not executable | Question offers straight/left priority, with different uturn obligation; no unique maneuver. Car from left turns right. |
| `ticket_11_15` | true | straight | `[]` | Flashing yellow, 2.1; tram left and truck right on secondary road; player straight first. |
| `ticket_12_13` | false | right | not executable | Requires traffic controller and pedestrians on destination road; substituted car/red light invalid. |
| `ticket_12_14` | false | unresolved | not executable | Any-direction emergency priority question; no selected maneuver. Requires special vehicle with active blue beacon and siren. |
| `ticket_12_15` | true | straight | `["npc_car"]` | Flashing yellow, 8.13 south-east; car right/left turn before player; tram left afterwards. |
| `ticket_13_13` | false | unresolved | not executable | Straight/right alternatives plus dedicated white tram signal; tram right turn is prohibited by its signal. |
| `ticket_13_14` | false | unresolved | not executable | Observer question about two turning vehicles; no unique player role. Truck and pedestrians absent from original scene. |
| `ticket_13_15` | false | left | not executable | Requires 8.13 and opposite left-turning truck; simultaneous non-conflicting left turns allowed while respecting truck priority. | | 8.13 north-east and opposite left-turning truck are representable, but the question tests starting a simultaneous non-conflicting left turn while respecting priority. A mandatory wait-until-truck-clears yield phase misrepresents this distinction; requires conflict-aware concurrent motion.
| `ticket_14_13` | false | unresolved | not executable | Requires signal transition and two already-clearing vehicles (car and truck); no unique player maneuver. |
| `ticket_14_14` | true | straight | `["tram_a","tram_b"]` | Restore A left and B right, both straight; yield to both. |
| `ticket_14_15` | true | left | `["npc_bus"]` | Restore opposite bus, keep car right, replace 2.4 with 2.1. |
| `ticket_15_13` | false | unresolved | not executable | Straight/left alternatives; green light and same-direction turning tram; left variant also requires entering tram tracks. |
| `ticket_15_14` | true | straight | `["tram_1"]` | Tram and car BOTH opposite/left turn; separated starting lanes; yield to tram. |
| `ticket_15_15` | true | left | `["npc_bus"]` | 8.13 south-east; bus right/left turn first, player left, car left/right turn last. |
| `ticket_16_13` | true | straight | `["tram_1"]` | Same opposite tram/car arrangement with green light; yield only to tram. |
| `ticket_16_14` | false | unresolved | not executable | Roundabout entry, sign 4.3, motorcycle and van on ring require dedicated circular route. |
| `ticket_16_15` | true | left | `["npc_car","npc_bus"]` | 2.4 + 8.13 west-east; car left/right turn and bus right/left turn both precede player. |
| `ticket_17_13` | true | right | `["npc_bus"]` | Red plus green right arrow; bus crosses from left before player turns right. |
| `ticket_17_14` | true | left | `["npc_truck_opposite","npc_truck_right"]` | Opposite truck straight, then right truck straight with amber beacon, then player left. |
| `ticket_17_15` | false | unresolved | not executable | Roundabout traversal/priority after entry requires circular geometry and sign 4.3; no ordinary-crossroad maneuver. |
| `ticket_18_13` | true | right | `[]` | Green with inactive 2.4 + 8.13 north-east; opposite car turns left after player right. |
| `ticket_18_14` | true | uturn | `["npc_car"]` | Choose explicitly permitted wait-first variant: car left turns right, then player uturn. |
| `ticket_18_15` | true | straight | `[]` | 2.1; opposite amber-beacon truck turns left after player straight. |
| `ticket_19_13` | true | straight | `["npc_car"]` | Red plus green straight arrow; yield to car from left turning right. |
| `ticket_19_14` | true | right | `[]` | Restore opposite left-turning motorcycle; car left straight; player right first. |
| `ticket_19_15` | false | unresolved | not executable | Abstract unknown-road-surface rule; no image, selected maneuver or actor set. Invented main-road sign contradicts premise. |
| `ticket_20_13` | true | left | `["npc_car","pedestrian"]` | Green, opposite car straight, pedestrian group on left destination road. |
| `ticket_20_14` | true | right | `[]` | Car from left straight; correct misleading oncoming label; player right first. |
| `ticket_20_15` | true | left | `["npc_moto","npc_bus","npc_car"]` | 2.4 + 8.13 west-north; motorcycle left, bus opposite, car right/left turn, then player left. |

## Source image index

Paths resolve relative to this document. Source question UUIDs permit checking
that positional ticket lookups still refer to the same question after updates.

| Situation | Source question UUID | Source image |
| --- | --- | --- |
| `ticket_1_13` | `d0063ffc0bad8476f04187c35b74b917` | [image](../assets/countries/ru/images/questions_ab/3bca6590a23e621ade16916c7de64e44.webp) |
| `ticket_1_14` | `09c728e5fcea9efdbd7c74d6f656b64d` | [image](../assets/countries/ru/images/questions_ab/6a8f690af1b507fc0b56db742709f1e8.webp) |
| `ticket_1_15` | `c64eefab25596af3056aa4b69e92516e` | [image](../assets/countries/ru/images/questions_ab/dd7e958840da9ddd1c102a65d8d5c03f.webp) |
| `ticket_2_13` | `a18d3dd1bdde77448b259039b3c9e140` | [image](../assets/countries/ru/images/questions_ab/d2f620a80735b4205843f9b3d26cecc6.webp) |
| `ticket_2_14` | `b54b690a22b4660ee3c1203fb2faff2a` | [image](../assets/countries/ru/images/questions_ab/effa4b8d198a74e7eeb2460bffca22dc.webp) |
| `ticket_2_15` | `b3a079f4b929c0d74201d89e99593ebf` | [image](../assets/countries/ru/images/questions_ab/ac0d572e2be79ff28310b579eba034eb.webp) |
| `ticket_3_13` | `d8e06d3ffac8f8d2adc551fc90f047ec` | [image](../assets/countries/ru/images/questions_ab/715412530dd5d75884feb036874bd759.webp) |
| `ticket_3_14` | `4d90ef76a000d062a331f81849de9e72` | [image](../assets/countries/ru/images/questions_ab/789a543e4b2c04f75abe487329d3fbda.webp) |
| `ticket_3_15` | `ce32e1f30e2693ddb2c13418c65d3c94` | [image](../assets/countries/ru/images/questions_ab/65f8dd2d800014138813ef003692857f.webp) |
| `ticket_4_13` | `6bfa8751fcae6a034406e9153f3cf9aa` | [image](../assets/countries/ru/images/questions_ab/8ffeae76681958aa7e73a4c1bbab6067.webp) |
| `ticket_4_14` | `f06fda7f7c28b7dcc624f1ece5ec0ee6` | [image](../assets/countries/ru/images/questions_ab/2bbc5bf511daa8989cf1c4d383a24a48.webp) |
| `ticket_4_15` | `d1512a1262810283918e40cb3495b9ad` | [image](../assets/countries/ru/images/questions_ab/7c620bbef7fd6afdf4be4e06ec5ed059.webp) |
| `ticket_5_13` | `c4547df34b93be087eee947c49c039de` | [image](../assets/countries/ru/images/questions_ab/80092d887fe7b764db1e0a7d64742489.webp) |
| `ticket_5_14` | `eab47901eebad4a8a34538c55ddf4093` | [image](../assets/countries/ru/images/questions_ab/e320da78c9d6109eca702486f83cf428.webp) |
| `ticket_5_15` | `19d2d8580ea765d6b86cfad8bf2df9a5` | [image](../assets/countries/ru/images/questions_ab/7df7c50058db5aa70e39af72c22dd9ba.webp) |
| `ticket_6_13` | `122a15b1675d4d194f6692702d285d63` | [image](../assets/countries/ru/images/questions_ab/8eaffcf3aa668202d1a61db01ba76ce4.webp) |
| `ticket_6_14` | `c8d62f5f28653dbf66a1c44fa29197c0` | [image](../assets/countries/ru/images/questions_ab/5b920a5d15ec9a4b3dbd200f36baee31.webp) |
| `ticket_6_15` | `8c3616674b46014b2338c7c719b2bc8d` | [image](../assets/countries/ru/images/questions_ab/6d10de1adbad3dfa4e761a78b170d887.webp) |
| `ticket_7_13` | `3b4b6092cf50c0e628ce0f2559df3f90` | [image](../assets/countries/ru/images/questions_ab/cf624ed2daa0947f0708e4c4b3dc7fc8.webp) |
| `ticket_7_14` | `059bf18cc5917313c7c2e73e20d41726` | [image](../assets/countries/ru/images/questions_ab/c149e9f2ca6afaf456691db1d9126d64.webp) |
| `ticket_7_15` | `d30d4ea921f8cf6d97e3e484725cd7f6` | [image](../assets/countries/ru/images/questions_ab/1f52b5842f4d43019a8c6aaa844432cd.webp) |
| `ticket_8_13` | `0da9f27691b4a0af365aa244ec7151f6` | [image](../assets/countries/ru/images/questions_ab/f101401b00f168cef0e8dd6b928d3976.webp) |
| `ticket_8_14` | `bcb9d002132e2fdf0b6bce53a4ce930a` | [image](../assets/countries/ru/images/questions_ab/30b317263f24b3d5d9c09f66bb1c0be1.webp) |
| `ticket_8_15` | `5bc912be09a0a696eb5c958b22569472` | [image](../assets/countries/ru/images/questions_ab/48062235ba530b29f020a2d7032a5bd8.webp) |
| `ticket_9_13` | `059bf18cc5917313c7c2e73e20d41726` | [image](../assets/countries/ru/images/questions_ab/c149e9f2ca6afaf456691db1d9126d64.webp) |
| `ticket_9_14` | `340eda677b699654d088c6951e2b884c` | [image](../assets/countries/ru/images/questions_ab/7696eff6f310158ee0bcfe0466a7ae39.webp) |
| `ticket_9_15` | `c64eefab25596af3056aa4b69e92516e` | [image](../assets/countries/ru/images/questions_ab/dd7e958840da9ddd1c102a65d8d5c03f.webp) |
| `ticket_10_13` | `194ef8a5284cdc1f00c190c4939e0943` | [image](../assets/countries/ru/images/questions_ab/7a60498d12d7f8dcb3630c7a3e3f7312.webp) |
| `ticket_10_14` | `868bee359407c776996137ee312c6e0e` | [image](../assets/countries/ru/images/questions_ab/46b0ff6c1e56e5f5f1fccee3cf90e2dd.webp) |
| `ticket_10_15` | `850f07c45a86afbcd4b4f09f017c6edc` | [image](../assets/countries/ru/images/questions_ab/5fe7a0f5a57a556d3012e3623f54e738.webp) |
| `ticket_11_13` | `f0e8b486407c5e33be8d2af0fb28a632` | [image](../assets/countries/ru/images/questions_ab/6e40b9704037f2543ec1560a342e4d71.webp) |
| `ticket_11_14` | `51626a271b7cc0a56285573791689c24` | [image](../assets/countries/ru/images/questions_ab/bc2a0abc48c739079cef9e12b2232b84.webp) |
| `ticket_11_15` | `2b4ce6ab61c50ff4b97eddf27dbc3699` | [image](../assets/countries/ru/images/questions_ab/243644fb9fbf5f97fcf695335ccebca0.webp) |
| `ticket_12_13` | `d72dcc8b68b6d5a24de5e002d7c2b9eb` | [image](../assets/countries/ru/images/questions_ab/15598370865aaa7a33d3221b521d408b.webp) |
| `ticket_12_14` | `e636c28bb84f0b1776a2da35ad1fe4f4` | [image](../assets/countries/ru/images/questions_ab/b0ba587013475581dd72731cbc816d54.webp) |
| `ticket_12_15` | `3b0778d393beaf09d4da768802a87a1d` | [image](../assets/countries/ru/images/questions_ab/1d55fde9be6beff7612cc3910c03b3fd.webp) |
| `ticket_13_13` | `25b3ae65d4bbdc58906e2bf2311c011b` | [image](../assets/countries/ru/images/questions_ab/657506834f78d08a97983b19a4cfd256.webp) |
| `ticket_13_14` | `2b2c8249eca052796e4ba9a714d5e8c2` | [image](../assets/countries/ru/images/questions_ab/ed9f1cd27af931a776a01e9dfc33f1cb.webp) |
| `ticket_13_15` | `fd37552baccdfe11681a8b7b81c7becb` | [image](../assets/countries/ru/images/questions_ab/2a89db503b07384ad4651da44028a545.webp) |
| `ticket_14_13` | `0d98d1d61f57dd4f66f07e984bb07668` | [image](../assets/countries/ru/images/questions_ab/dd15c5c92a1b7c94fdb3e7dc31b52742.webp) |
| `ticket_14_14` | `f110bdab640dcf5443d62c6b0be3d76e` | [image](../assets/countries/ru/images/questions_ab/11f039da164d6a869116a1ecf0aa5a18.webp) |
| `ticket_14_15` | `799fcc9cd0bb95dcd359cba8e53d205a` | [image](../assets/countries/ru/images/questions_ab/84e8cb2bde0226c0b037e892ac66149a.webp) |
| `ticket_15_13` | `0cb2b478dc17e3d0ecb6e342d5fe65bd` | [image](../assets/countries/ru/images/questions_ab/972568e0368e212d3e544299c1cf9e6c.webp) |
| `ticket_15_14` | `300e9333ae2c626e63f181922b27eff9` | [image](../assets/countries/ru/images/questions_ab/027cbb3db9e957610325cddf7cf6a5ed.webp) |
| `ticket_15_15` | `1ff83cfa25d8634e88ee581fe7e7ba35` | [image](../assets/countries/ru/images/questions_ab/1d93395fcc55702c1381825d1b12da43.webp) |
| `ticket_16_13` | `a3ea7d0ff65e34bd919d92c07e55403e` | [image](../assets/countries/ru/images/questions_ab/17ca1dd7faf1c1ea2680f5d3a1620c56.webp) |
| `ticket_16_14` | `668d7512cacd89f836cb82d051090eed` | [image](../assets/countries/ru/images/questions_ab/7b1c408b98194dd5cdadf50edd222bbf.webp) |
| `ticket_16_15` | `f4792cb76559bd9ab2ce7ff377db691c` | [image](../assets/countries/ru/images/questions_ab/238e4c24cb2fac30bce698f879249e9f.webp) |
| `ticket_17_13` | `c871839f6ef53eaf9f70aea52ed1a1c0` | [image](../assets/countries/ru/images/questions_ab/172e3ccb89e814163168d4f01963b001.webp) |
| `ticket_17_14` | `7e5563b75926bacbf1e5b9230f44bcbe` | [image](../assets/countries/ru/images/questions_ab/271363aadf7805f75a3a2fb5309db83a.webp) |
| `ticket_17_15` | `1822ac76f46db7af1683366f081492a4` | [image](../assets/countries/ru/images/questions_ab/2f54bd9e30e950139dfe9fa202fa6d36.webp) |
| `ticket_18_13` | `014098be5a4ec93894a054e03e2a5d04` | [image](../assets/countries/ru/images/questions_ab/a926e2a439dd3ef6d65198b969d5625d.webp) |
| `ticket_18_14` | `b1a042b320744714cbef98b7313cf244` | [image](../assets/countries/ru/images/questions_ab/2e09e33eff9895baa99769e1239e883f.webp) |
| `ticket_18_15` | `145772798a096526e5d2d9b3b01431e3` | [image](../assets/countries/ru/images/questions_ab/609b0f853107093d74ec48509823337e.webp) |
| `ticket_19_13` | `6e816892a71cd93ee5e905c4355bfdee` | [image](../assets/countries/ru/images/questions_ab/9a24813a3292e581eb60ee0fde93d54c.webp) |
| `ticket_19_14` | `e17b107b4651ebfd63b330cdd5d3a776` | [image](../assets/countries/ru/images/questions_ab/4fc7fcf44288e61dd11e2248f6f3cd79.webp) |
| `ticket_19_15` | `482eaefb70b2a4832dac632b70810951` | none (abstract question) |
| `ticket_20_13` | `e864d1ee6774acf69d5f8b24bcf221b7` | [image](../assets/countries/ru/images/questions_ab/e2b9425804c73c5ca16eb6277d7a44d2.webp) |
| `ticket_20_14` | `69e32b0a26f5ca5233e683e3aa0b6067` | [image](../assets/countries/ru/images/questions_ab/d7c90e14e7bec22a2c8515b5cc3fd16d.webp) |
| `ticket_20_15` | `41fe413138ce960636eb45afa5f9814f` | [image](../assets/countries/ru/images/questions_ab/6213aca51e52eb845a5608a69d366076.webp) |

## Validation and parent follow-up

Data validation checks exact 60-key coverage against the current SITUATIONS,
supported enum values, unique actor IDs, referential integrity of every reviewed
yieldTo, complete override fields, exclusion reasons, source-image existence,
and maneuver counts. JavaScript is evaluated in an isolated window object.

Parent still needs to apply replacements before scene construction, filter
strictly on reviewed, consume route metadata, refresh legends, implement the
promised special/amber signals, directional plates and arrow sections, and
visually verify turns, tram lanes, pedestrians and player/NPC uturns. Do not enable an excluded scene until its listed limitation has a
source-backed implementation.

## Tickets 21–40 (second batch)

Scope: questions 13–15 of tickets 21–40 (60 more source questions), matched to
questions_ab.json the same way; all titles, options, correct indexes and
explanations are copied verbatim from the source. Each enabled scene was built
after viewing its source image; sign 8.13 branches are read from the plate in
driver-view coordinates. 31 entries are reviewed, 29 excluded with reasons
(traffic controllers, roundabout, divided roads with mid-intersection signals,
observation questions over several maneuvers, staged mid-maneuver yielding,
a dirt road, a horse-drawn cart, a tram alongside the player). Two T-junctions
(39_14, 40_15) are schematised as crossroads: the extra exit does not change the
priority in either question. 35_14 shows a motorcycle dashboard in the source;
the player keeps the selected car.

| Situation | reviewed | maneuver | yieldTo | Repair or exclusion reason |
| --- | --- | --- | --- | --- |
| `ticket_21_13` | true | left | `["npc_special", "npc_moto"]` | Green with inactive 2.1; special crosses from left on red with blue beacon AND siren; opposite motorcycle straight; player last. |
| `ticket_21_14` | true | left | `["npc_car", "npc_moto"]` | Equal crossroad; opposite car turns right (non-conflicting) first, motorcycle from right second, player last. |
| `ticket_21_15` | false | straight | `[]` | Truck exits a dirt road (unpaved side road); the renderer has no unpaved approach and the answer depends on it. |
| `ticket_22_13` | false | left | `[]` | Divided road with a second signal inside the intersection; medians and mid-intersection lights are not modelled. |
| `ticket_22_14` | false | unresolved | `[]` | Observation question over two maneuvers (left and straight); no unique player maneuver. |
| `ticket_22_15` | false | right | `[]` | Correct answer requires judging interference with a truck mid-turn; staged concurrent yielding is not modelled. |
| `ticket_23_13` | false | right | `[]` | Traffic controller. |
| `ticket_23_14` | true | straight | `[]` | Equal crossroad; opposite car turns left and yields; player straight first. |
| `ticket_23_15` | true | left | `["npc_bus"]` | 2.1 + 8.13 south-east; bus from right on main road is the right-hand obstacle; car from left is secondary. |
| `ticket_24_13` | true | left | `["tram_1", "npc_car"]` | Green; tram from left first, opposite car straight next, player left last. Lane sign 5.15.1 omitted (no priority effect). |
| `ticket_24_14` | false | straight | `[]` | Answer is mutual agreement between drivers; no deterministic yield order. |
| `ticket_24_15` | false | unresolved | `[]` | Observation question over two maneuvers (left and right); no unique player maneuver. |
| `ticket_25_13` | false | unresolved | `[]` | No image; theory question about signs cancelled by signals. |
| `ticket_25_14` | true | right | `["cyclist", "pedestrian"]` | Right turn; cyclist alongside player; pedestrians cross right destination road (same layout as 1_13, unregulated). |
| `ticket_25_15` | true | left | `["npc_car"]` | 2.1 + 8.13 south-east; car from right on main first, player second; bus (opposite) and motorcycle (left) are secondary. |
| `ticket_26_13` | false | left | `[]` | Divided road with a stop line and signal on the median; not modelled. |
| `ticket_26_14` | true | left | `["npc_truck", "npc_car"]` | Equal crossroad; opposite truck has no right-hand obstacle and goes first, car from right second, player last. |
| `ticket_26_15` | true | straight | `["npc_bus", "npc_car"]` | 2.4 + 8.13 north-east; opposite bus and car from right on main road; motorcycle from left is secondary and yields to player. |
| `ticket_27_13` | false | right | `[]` | Traffic controller. |
| `ticket_27_14` | false | unresolved | `[]` | Roundabout. |
| `ticket_27_15` | true | left | `["npc_bus", "npc_car"]` | Same scene as 26_15 with a left turn; player after bus and car, before the motorcycle. |
| `ticket_28_13` | true | left | `["tram_1", "npc_car"]` | Green; opposite tram turns left first, opposite car turns right concurrently; player last (explicit positions like 15_14). |
| `ticket_28_14` | false | unresolved | `[]` | Observation question over two maneuvers (straight and right); no unique player maneuver. |
| `ticket_28_15` | true | uturn | `["npc_truck"]` | 2.1 + 8.13 south-east; truck from right on main first, player uturn second, opposite car (secondary) last. |
| `ticket_29_13` | false | unresolved | `[]` | Observation question about another driver's maneuvers. |
| `ticket_29_14` | false | left | `[]` | Turn from tram tracks of the same direction; lane/track selection is not modelled. |
| `ticket_29_15` | true | straight | `["npc_bus", "npc_car"]` | 2.4 + 8.13 north-east; opposite bus and car from right are on the main road; player yields to both. |
| `ticket_30_13` | false | unresolved | `[]` | Observation question over two maneuvers (left and uturn); no unique player maneuver. |
| `ticket_30_14` | false | straight | `[]` | Horse-drawn cart actor type is not available. |
| `ticket_30_15` | true | left | `[]` | 2.1 + 8.13 south-east; car from right turns right (no conflict), player first; motorcycle and bus are secondary. |
| `ticket_31_13` | false | left | `[]` | Traffic controller. |
| `ticket_31_14` | true | straight | `["tram_1", "npc_truck"]` | Equal crossroad; tram from left has priority, truck from right is the right-hand obstacle; conservative serial order. |
| `ticket_31_15` | true | straight | `["npc_moto", "npc_bus", "npc_car"]` | 2.4 + 8.13 north-west; motorcycle from left and opposite bus on main road, then car from right; player last. |
| `ticket_32_13` | true | left | `["npc_bus"]` | Green with inactive 2.4; opposite bus straight has priority; truck with amber beacon waits at red on the right. |
| `ticket_32_14` | false | uturn | `[]` | Correct answer requires entering first and yielding mid-maneuver; staged yielding is not modelled. |
| `ticket_32_15` | false | straight | `[]` | Tram travels alongside the player on the same approach; that placement is not in the scene vocabulary. |
| `ticket_33_13` | false | right | `[]` | Traffic controller. |
| `ticket_33_14` | false | left | `[]` | Correct answer requires entering first and yielding mid-maneuver; staged yielding is not modelled. |
| `ticket_33_15` | true | straight | `["npc_car", "npc_truck"]` | 2.4 + 8.13 north-east; opposite car and truck from right are on the main road. |
| `ticket_34_13` | false | straight | `[]` | Traffic controller. |
| `ticket_34_14` | true | left | `["npc_car"]` | Equal crossroad; car from right is the only right-hand obstacle; motorcycle from left yields to player. |
| `ticket_34_15` | true | left | `["npc_bus", "npc_car"]` | 2.4 + 8.13 north-west; bus from left (turning right) and opposite car are on the main road. |
| `ticket_35_13` | false | unresolved | `[]` | Observation question over several maneuvers; no unique player maneuver. |
| `ticket_35_14` | true | straight | `["npc_truck"]` | Equal crossroad; truck from right has priority. |
| `ticket_35_15` | true | left | `["npc_special"]` | 2.1 + 8.13 south-west; special vehicle from right with blue beacon AND siren first; player (main) before opposite truck (secondary). |
| `ticket_36_13` | false | right | `[]` | Traffic controller. |
| `ticket_36_14` | false | unresolved | `[]` | Observation question over two maneuvers; tram-track lane change is not modelled. |
| `ticket_36_15` | true | left | `["npc_truck"]` | Unregulated (light off) with 2.1; opposite truck on main road first, player second, car from right (secondary) last. |
| `ticket_37_13` | false | right | `[]` | Requires stopping inside the intersection before the crosswalk; staged stop is not modelled. |
| `ticket_37_14` | false | unresolved | `[]` | Observation question over several maneuvers; no unique player maneuver. |
| `ticket_37_15` | true | straight | `["tram_1"]` | 2.1; opposite tram on the same main road turns left and has priority over the trackless player. |
| `ticket_38_13` | true | left | `["npc_special", "npc_car"]` | Green with inactive 2.1 + 8.13; special from right with blue beacon AND siren first, then opposite car straight, player last. |
| `ticket_38_14` | false | unresolved | `[]` | Observation question over two maneuvers (left and straight); no unique player maneuver. |
| `ticket_38_15` | false | right | `[]` | Correct answer waits for the truck to begin its left turn; staged concurrent motion is not modelled. |
| `ticket_39_13` | true | straight | `["tram_1"]` | Green with inactive 2.1; tram from left in equal conditions has priority. |
| `ticket_39_14` | true | left | `["npc_car"]` | Equal T-junction schematised as a crossroad; car from right is the right-hand obstacle. |
| `ticket_39_15` | true | straight | `["npc_car"]` | 2.1 + 8.13 south-east; car from right on main first; truck (opposite) and motorcycle (left) are secondary. |
| `ticket_40_13` | true | right | `["tram_b", "tram_a"]` | Green; both trams have simultaneous right of way and precede the player's right turn. |
| `ticket_40_14` | true | straight | `["npc_moto"]` | Equal crossroad; motorcycle from right first; truck with amber beacon (no priority) turns left after player. |
| `ticket_40_15` | true | left | `["npc_bus", "npc_truck"]` | 2.4 at a T-junction schematised as a crossroad; both vehicles on the crossed road have priority. |

## Сверка поворотников с картинками билетов (2026-09-22)

Все 67 сценариев просмотрены по исходным картинкам: сторона мигающего
указателя у каждого ТС сверена с `targetAction` в игре. Исправлено 9 машин:
21.14 (встречный — налево), 25.15, 26.15, 27.15, 30.15, 34.14 (машина справа —
налево), 40.15 (грузовик справа — налево), 36.15, 40.14 (встречный грузовик —
направо). Звёздочки на светофорах (мигающий жёлтый, 11.15) и маячки на
грузовиках (5.15, 17.14, 18.15, 40.14) — не указатели поворота.
Раньше указатели были только у машин дорожных ситуаций; теперь у каждого
ТС (кроме пешеходов/велосипедистов), сторона — по `targetAction`.

## Перекрёстки с односторонним движением

`oneWay: 'to_right' | 'to_left'` у сценария (направление движения по
поперечной дороге с точки зрения игрока): на поперечной дороге нет осевой
1.1, только линия 1.5; на плече «против потока» — знак 3.1 лицом к
перекрёстку. `trajectories` — нарисованные на асфальте траектории с буквами,
как на картинке билета. Сценарии: 18.8 (5.7.1), 14.8 (5.7.2). 28.6 не взят —
нужен регулировщик, которого в движке нет.
