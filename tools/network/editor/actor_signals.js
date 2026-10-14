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
  return { supports, hazards, setHazards, setMoving, pulse };
})();
if (typeof module !== "undefined") module.exports = ActorSignals;
