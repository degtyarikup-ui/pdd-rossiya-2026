import {noteFraming} from './note-framing.mjs?v=20261116-framing2';
// Every available note has an image. Coordinates are column / row in each atlas.
const atlas = (file, rows, names) => Object.fromEntries(names.map((name, index) => [name, {
  file: `./public/assets/${file}`, columns: 3, rows, column: index % 3, row: Math.floor(index / 3)
}]));

export const noteArtwork = {
  ...atlas('ingredients.webp', 3, ['Грейпфрут','Ирис','Замша','Мандарин','Роза','Ваниль','Чёрная смородина','Жасмин','Кедр']),
  ...atlas('notes-fresh.webp', 3, ['Бергамот','Груша','Малина','Мята','Цветок апельсина','Яблоко','Пион','Дыня','Фиалка']),
  ...atlas('notes-warm.webp', 3, ['Амбра','Мускус','Кардамон','Сандал','Имбирь','Мускатный орех','Розовый перец','Бензоин','Лабданум']),
  ...atlas('notes-remaining.webp', 2, ['Апельсин','Древесные ноты','Зелёный чай','Капучино','Морские ноты','Замша']),
  ...Object.fromEntries(Object.entries({
    'Розовый перец': 'pink-pepper-v2.webp',
    'Мускус': 'musk-accord-v2.webp',
    'Амбра': 'amber-accord-v3.webp',
    'Ваниль': 'vanilla-v3.webp',
    'Лабданум': 'labdanum-v2.webp'
  }).map(([name, file]) => [name, {file: `./public/assets/${file}`, columns: 1, rows: 1, column: 0, row: 0}])),
  'Сандал': {file: './public/assets/sandalwood-v2.webp', columns: 1, rows: 1, column: 0, row: 0}
};

// Unused original atlas cells are not exposed as extra notes.
delete noteArtwork['Мандарин'];
delete noteArtwork['Роза'];

for (const [name, art] of Object.entries(noteArtwork)) art.frame = noteFraming[name];
