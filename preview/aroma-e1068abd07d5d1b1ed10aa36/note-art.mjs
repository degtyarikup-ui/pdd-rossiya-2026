import {noteFiles} from './note-files.mjs';
import {noteFraming} from './note-framing.mjs?v=20261118-catalog1';

export const noteArtwork = Object.fromEntries(Object.entries(noteFiles).map(([name, file]) => [
  name, {
    file: `./public/assets/notes/${file}`,
    columns: 1, rows: 1, column: 0, row: 0,
    frame: noteFraming[name],
  },
]));
