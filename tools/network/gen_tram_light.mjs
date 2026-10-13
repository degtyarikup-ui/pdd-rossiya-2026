import * as THREE from "../../../parking-video-generator/node_modules/three/build/three.module.js";
import { GLTFExporter } from "../../../parking-video-generator/node_modules/three/examples/jsm/exporters/GLTFExporter.js";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

class NodeFileReader {
  readAsArrayBuffer(blob) {
    blob.arrayBuffer().then(buf => {
      this.result = buf;
      if (this.onloadend) this.onloadend();
      if (this.onload) this.onload();
    });
  }
}
globalThis.FileReader = NodeFileReader;

export function createTrafficLightTram() {
  const root = new THREE.Group();
  root.name = "traffic_light";

  // Materials matching project conventions
  const metalMat = new THREE.MeshStandardMaterial({ name: "c334155", color: 0x334155, roughness: 0.5, metalness: 0.5 });
  const housingMat = new THREE.MeshStandardMaterial({ name: "c1e293b", color: 0x1E293B, roughness: 0.5, metalness: 0.5 });
  const visorMat = new THREE.MeshStandardMaterial({ name: "c1e293b", color: 0x1E293B, roughness: 0.5, metalness: 0.5, side: THREE.DoubleSide });
  const plateMat = new THREE.MeshStandardMaterial({ name: "c111827", color: 0x111827, roughness: 0.5, metalness: 0.5 });
  const rimMat = new THREE.MeshStandardMaterial({ name: "cf1f5f9", color: 0xF1F5F9, roughness: 0.5, metalness: 0.5 });

  // Lamp materials
  const redMat = new THREE.MeshBasicMaterial({ name: "c351719", color: 0x351719 }); // dark red off
  const yellowMat = new THREE.MeshBasicMaterial({ name: "c352d14", color: 0x352D14 }); // dark yellow off
  const greenMat = new THREE.MeshBasicMaterial({ name: "c36ff88", color: 0x36FF88 }); // lit green
  const lunarLitMat = new THREE.MeshBasicMaterial({ name: "ceaf4fc", color: 0xF0F6FF }); // lit lunar-white
  const lunarDarkMat = new THREE.MeshBasicMaterial({ name: "c20252c", color: 0x20252C }); // off lunar-white

  // 1. Mast / Pole (up to 5.4m)
  const postGeom = new THREE.CylinderGeometry(0.08, 0.08, 5.4, 12);
  const post = new THREE.Mesh(postGeom, metalMat);
  post.name = "c334155";
  post.position.set(0, 2.70, 0);
  root.add(post);

  // Terminal box on pole (below traffic light)
  const termGeom = new THREE.BoxGeometry(0.24, 0.28, 0.22);
  const term = new THREE.Mesh(termGeom, housingMat);
  term.name = "c1e293b";
  term.position.set(0, 2.05, 0.16);
  root.add(term);

  // 2. Lower Housing Box (standard 3-aspect)
  const lowerBox = new THREE.Mesh(new THREE.BoxGeometry(0.65, 1.6, 0.4), housingMat);
  lowerBox.name = "c1e293b";
  lowerBox.position.set(0, 3.4, 0.25);
  root.add(lowerBox);

  // Lower Back Plate & White Rim (y=3.4, height 1.96 -> top is y=4.38)
  const lowerPlate = new THREE.Mesh(new THREE.BoxGeometry(0.95, 1.9, 0.03), plateMat);
  lowerPlate.name = "c111827";
  lowerPlate.position.set(0, 3.4, 0.03);
  root.add(lowerPlate);

  const lowerRim = new THREE.Mesh(new THREE.BoxGeometry(1.01, 1.96, 0.02), rimMat);
  lowerRim.name = "cf1f5f9";
  lowerRim.position.set(0, 3.4, 0.01);
  root.add(lowerRim);

  // 3. Lower Lamps & Visors
  function createVehicularVisor(y) {
    const v = new THREE.Mesh(new THREE.CylinderGeometry(0.26, 0.26, 0.26, 16, 1, true, -Math.PI / 2, Math.PI), visorMat);
    v.name = "c1e293b";
    v.rotation.x = -Math.PI / 2;
    v.position.set(0, y, 0.58);
    return v;
  }

  function makeLampGeo(r = 0.21) {
    const geo = new THREE.CylinderGeometry(r, r, 0.06, 20);
    geo.rotateX(Math.PI / 2);
    return geo;
  }

  // Red
  const redNode = new THREE.Group();
  redNode.name = "lamp_red";
  redNode.position.set(0, 3.85, 0.46);
  const redMesh = new THREE.Mesh(makeLampGeo(0.21), redMat);
  redMesh.name = "lamp_red:c351719";
  redNode.add(redMesh);
  root.add(redNode);
  root.add(createVehicularVisor(3.85));

  // Yellow
  const yellowNode = new THREE.Group();
  yellowNode.name = "lamp_yellow";
  yellowNode.position.set(0, 3.40, 0.46);
  const yellowMesh = new THREE.Mesh(makeLampGeo(0.21), yellowMat);
  yellowMesh.name = "lamp_yellow:c352d14";
  yellowNode.add(yellowMesh);
  root.add(yellowNode);
  root.add(createVehicularVisor(3.40));

  // Green
  const greenNode = new THREE.Group();
  greenNode.name = "lamp_green";
  greenNode.position.set(0, 2.95, 0.46);
  const greenMesh = new THREE.Mesh(makeLampGeo(0.21), greenMat);
  greenMesh.name = "lamp_green:c36ff88";
  greenNode.add(greenMesh);
  root.add(greenNode);
  root.add(createVehicularVisor(2.95));

  // 4. Upper Section (T-5 Tram Light)
  // Flush mount directly on top of lower rim:
  // Stem: y from 4.38 to 4.82 (center 4.60), width 0.65, height 0.44
  const tramStem = new THREE.Mesh(new THREE.BoxGeometry(0.65, 0.44, 0.4), housingMat);
  tramStem.name = "c1e293b";
  tramStem.position.set(0, 4.60, 0.25);
  root.add(tramStem);

  // Top bar: y from 4.82 to 5.30 (center 5.06), width 1.40, height 0.48
  const tramTopBar = new THREE.Mesh(new THREE.BoxGeometry(1.40, 0.48, 0.4), housingMat);
  tramTopBar.name = "c1e293b";
  tramTopBar.position.set(0, 5.06, 0.25);
  root.add(tramTopBar);

  // Angled side wedges connecting stem to top bar (left and right)
  function createWedge(left = true) {
    const shape = new THREE.Shape();
    const s = left ? -1 : 1;
    shape.moveTo(s * 0.325, 4.38);
    shape.lineTo(s * 0.70, 4.82);
    shape.lineTo(s * 0.325, 4.82);
    shape.closePath();
    const geom = new THREE.ExtrudeGeometry(shape, { depth: 0.4, bevelEnabled: false });
    geom.translate(0, 0, 0.05);
    const m = new THREE.Mesh(geom, housingMat);
    m.name = "c1e293b";
    return m;
  }
  root.add(createWedge(true));
  root.add(createWedge(false));

  // Upper Back Plate (T-shaped shield)
  const plateShape = new THREE.Shape();
  plateShape.moveTo(-0.40, 4.38);
  plateShape.lineTo(-0.76, 4.82);
  plateShape.lineTo(-0.76, 5.34);
  plateShape.lineTo(0.76, 5.34);
  plateShape.lineTo(0.76, 4.82);
  plateShape.lineTo(0.40, 4.38);
  plateShape.closePath();
  const plateGeom = new THREE.ExtrudeGeometry(plateShape, { depth: 0.03, bevelEnabled: false });
  plateGeom.translate(0, 0, 0.015);
  const upperPlate = new THREE.Mesh(plateGeom, plateMat);
  upperPlate.name = "c111827";
  root.add(upperPlate);

  // 5. Upper 4 Tram Lamps & Visors
  function createTramVisor(x, y) {
    const v = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 0.24, 16, 1, true, -Math.PI / 2, Math.PI), visorMat);
    v.name = "c1e293b";
    v.rotation.x = -Math.PI / 2;
    v.position.set(x, y, 0.58);
    return v;
  }

  // A. Bottom lamp (x=0, y=4.60) -> LIT by default (straight)
  const tramBottom = new THREE.Group();
  tramBottom.name = "lamp_tram_bottom";
  tramBottom.position.set(0, 4.60, 0.46);
  const meshTB = new THREE.Mesh(makeLampGeo(0.18), lunarLitMat.clone());
  meshTB.name = "lamp_tram_bottom:ceaf4fc";
  tramBottom.add(meshTB);
  root.add(tramBottom);
  root.add(createTramVisor(0, 4.60));

  // B. Top Mid lamp (x=0, y=5.06) -> LIT by default (straight)
  const tramMid = new THREE.Group();
  tramMid.name = "lamp_tram_mid";
  tramMid.position.set(0, 5.06, 0.46);
  const meshTM = new THREE.Mesh(makeLampGeo(0.18), lunarLitMat.clone());
  meshTM.name = "lamp_tram_mid:ceaf4fc";
  tramMid.add(meshTM);
  root.add(tramMid);
  root.add(createTramVisor(0, 5.06));

  // C. Top Left lamp (x=-0.42, y=5.06) -> OFF by default
  const tramLeft = new THREE.Group();
  tramLeft.name = "lamp_tram_left";
  tramLeft.position.set(-0.42, 5.06, 0.46);
  const meshTL = new THREE.Mesh(makeLampGeo(0.18), lunarDarkMat.clone());
  meshTL.name = "lamp_tram_left:c20252c";
  tramLeft.add(meshTL);
  root.add(tramLeft);
  root.add(createTramVisor(-0.42, 5.06));

  // D. Top Right lamp (x=+0.42, y=5.06) -> OFF by default
  const tramRight = new THREE.Group();
  tramRight.name = "lamp_tram_right";
  tramRight.position.set(0.42, 5.06, 0.46);
  const meshTR = new THREE.Mesh(makeLampGeo(0.18), lunarDarkMat.clone());
  meshTR.name = "lamp_tram_right:c20252c";
  tramRight.add(meshTR);
  root.add(tramRight);
  root.add(createTramVisor(0.42, 5.06));

  return root;
}

if (process.argv[1] && process.argv[1].endsWith("gen_tram_light.mjs")) {
  const model = createTrafficLightTram();
  const exporter = new GLTFExporter();
  exporter.parse(model, (glb) => {
    const buf = Buffer.from(glb);
    const outDir = path.resolve(__dirname, "../../game_godot/models/street");
    if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
    const outPath = path.join(outDir, "traffic_light_tram.glb");
    fs.writeFileSync(outPath, buf);
    console.log("Wrote traffic_light_tram.glb, size:", buf.length);

    // Also write to situations templates / parts for ticket_6_13 and ticket_13_13
    const sitDirs = [
      path.resolve(__dirname, "../../game_godot/situations/ticket_6_13"),
      path.resolve(__dirname, "../../game_godot/situations/ticket_13_13")
    ];
    for (const sDir of sitDirs) {
      if (fs.existsSync(sDir)) {
        const partsDir = path.join(sDir, "parts");
        if (!fs.existsSync(partsDir)) fs.mkdirSync(partsDir, { recursive: true });
        fs.writeFileSync(path.join(partsDir, "light_0.glb"), buf);
        fs.writeFileSync(path.join(sDir, "light_0.glb"), buf);
        console.log("Copied to", sDir);
      }
    }
  }, (err) => console.error(err), { binary: true });
}
