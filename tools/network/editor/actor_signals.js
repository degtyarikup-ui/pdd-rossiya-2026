// Authored vehicle signals; explicit settings override archived question defaults.
const ActorSignals = (() => {
  const KINDS = new Set(["car", "truck", "bus", "van", "special", "tanker", "motorcycle", "tram", "tractor"]);
  const supports = type => KINDS.has(type);
  function hazards(actor) {
    if (!supports(actor.type)) return false;
    const behaviour = actor.behaviour || {};
    return Object.prototype.hasOwnProperty.call(behaviour, "hazards")
      ? behaviour.hazards === true : behaviour.config?.hazard === true;
  }
  function setHazards(actor, enabled) {
    actor.behaviour = { ...(actor.behaviour || {}), hazards: !!enabled };
  }
  const MANUAL = new Set(["left", "right", "off"]);
  const mode = actor => MANUAL.has(actor.behaviour?.turnSignal) ? actor.behaviour.turnSignal : "auto";
  function setTurn(actor, value) {
    if (!MANUAL.has(value) && value !== "auto") return;
    actor.behaviour = { ...(actor.behaviour || {}) };
    if (MANUAL.has(value)) actor.behaviour.turnSignal = value;
    else if (value === "auto") delete actor.behaviour.turnSignal;
  }
  const maneuverSide = way => ["left", "turn_left", "turn_left_at_junction", "uturn"].includes(way) ? "L"
    : ["right", "turn_right"].includes(way) ? "R" : "";
  function side(actor, scene = {}) {
    if (!supports(actor.type)) return "";
    const setting = mode(actor);
    if (setting !== "auto") return maneuverSide(setting);
    const explicitWay = ["left", "right", "straight", "uturn"].includes(actor.way);
    const plan = actor.behaviour?.signalPlan;
    if (Array.isArray(plan) && plan.length) {
      const span = plan.find(s => Number(s.from) <= 0 && Number(s.to) > 0);
      return span ? maneuverSide(explicitWay ? actor.way : span.side) : "";
    }
    if (explicitWay) return maneuverSide(actor.way);
    const target = actor.behaviour?.config?.targetAction;
    if (target != null) return maneuverSide(target);
    const points = scene.routes?.find(r => r.id === actor.route)?.points || [];
    if (points.length < 3) return "";
    const a = points[1].map((v,i) => v - points[0][i]);
    const b = points.at(-1).map((v,i) => v - points.at(-2)[i]);
    if (Math.hypot(...a) < .01 || Math.hypot(...b) < .01) return "";
    const angle = Math.atan2(-(a[0]*b[1] - a[1]*b[0]), a[0]*b[0] + a[1]*b[1]);
    return Math.abs(angle) < Math.PI/6 ? "" : angle > 0 ? "L" : "R";
  }
  function litSides(actor, scene, seconds) {
    const on = pulse(seconds), both = hazards(actor), turn = side(actor,scene);
    return {left:on && (both || turn === "L"), right:on && (both || turn === "R")};
  }
  function setMoving(actor, moving) {
    const previous = actor.behaviour || {};
    actor.behaviour = { ...previous, staysPut: !moving };
    // Old parked-question templates also stop forever at distance zero.
    // Clear that hold when the author explicitly turns them into moving cars.
    if (moving && previous.staysPut && previous.stopFor === "inf") {
      actor.behaviour.stopAtDistance = null;
      actor.behaviour.stopFor = null;
    }
  }
  const pulse = seconds => Math.floor(seconds * 3) % 2 === 0;
  return { supports, hazards, setHazards, mode, setTurn, side, litSides, setMoving, pulse };
})();
if (typeof module !== "undefined") module.exports = ActorSignals;
