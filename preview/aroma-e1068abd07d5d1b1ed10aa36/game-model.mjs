const MAX_NOTES = 3;

// Scope the catalog before deriving both selectable notes and final matches.
export function getPerfumesForGender(perfumes, gender = 'women') {
  if (gender !== 'women' && gender !== 'men') {
    throw new RangeError('Fragrance gender must be women or men.');
  }
  return perfumes.filter(perfume => perfume.gender === gender);
}

function validChoices(choices) {
  return Array.isArray(choices)
    && choices.length <= MAX_NOTES
    && choices.every(note => typeof note === 'string' && note.trim().length > 0)
    && new Set(choices).size === choices.length;
}

export function isCompleteSelection(choices) {
  return validChoices(choices) && choices.length === MAX_NOTES;
}

export function getMatches(perfumes, choices = []) {
  if (!validChoices(choices)) return [];
  return perfumes.filter(perfume => choices.every(note => perfume.notes.includes(note)));
}

export function getAvailableNotes(perfumes, choices = []) {
  if (!validChoices(choices) || choices.length === MAX_NOTES) return [];
  const selected = new Set(choices);
  return [...new Set(getMatches(perfumes, choices).flatMap(perfume => perfume.notes))]
    .filter(note => !selected.has(note));
}

// Editing a step discards that step and all choices dependent on it.
export function replaceFrom(choices, index) {
  if (!validChoices(choices) || !Number.isInteger(index) || index < 0 || index > choices.length) {
    throw new RangeError('A step index must be between 0 and the number of selected notes.');
  }
  return choices.slice(0, index);
}

// Notes are equal-weight ingredients: deleting one keeps every other choice.
export function removeNoteAt(choices, index) {
  if (!validChoices(choices) || !Number.isInteger(index) || index < 0 || index >= choices.length) {
    throw new RangeError('A note index must identify an existing selected note.');
  }
  return [...choices.slice(0, index), ...choices.slice(index + 1)];
}
