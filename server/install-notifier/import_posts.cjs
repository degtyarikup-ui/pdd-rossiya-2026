const { execSync } = require('child_process');

const posts = [
  {
    id: "post-1",
    scheduledDate: "2026-08-21",
    text: "Электросамокатчики, которые носятся по узким тротуарам под 30 км/ч — вы сохранились перед выходом из дома или у вас просто запчасти лишние? 🛴💥 \nДавно пора приравнять их к мопедам, выдавать права и выгнать на проезжую часть к машинам. Кто за?",
    status: "draft"
  },
  {
    id: "post-2",
    scheduledDate: "2026-08-22",
    text: "90% водителей со стажем сейчас лишатся прав. 🛑\nПопробуйте не завалить этот базовый вопрос из официального экзамена ГИБДД. Кто проедет перекресток первым? \nПишите свой вариант, только чур в правила не подглядывать! Посмотрим, сколько тут реальных знатоков. 👇",
    status: "draft"
  },
  {
    id: "post-3",
    scheduledDate: "2026-08-23",
    text: "Среднестатистический российский спальник в 23:00. \nКак вы вообще выезжаете по утрам, мастера тетриса? 🧱🚗 У кого во дворе такая же боль?",
    status: "draft"
  },
  {
    id: "post-4",
    scheduledDate: "2026-08-24",
    text: "Опять пошли разговоры про возвращение штрафов за превышение средней скорости. Кажется, камеры уже не окупаются и кто-то решил пополнить бюджет за счет водителей. \nДавно пора или очередной бред? Как будете выкручиваться на трассах? 📷🏎️",
    status: "draft"
  },
  {
    id: "post-5",
    scheduledDate: "2026-08-25",
    text: "Вопрос к тем, кто каждый день за рулем. Кого сейчас на дорогах боятся и ненавидят больше: старые тонированные БМВ или новенькие китайские кроссоверы, которые едут как хотят? \nКажется, лидер сменился 🤔",
    status: "draft"
  },
  {
    id: "post-6",
    scheduledDate: "2026-08-26",
    text: "Вспомните свой экзамен по вождению в городе. Какая была самая тупая причина, по которой вы или ваши знакомые завалили сдачу и отправились на пересдачу? \nНачну: девушка на моем потоке не уступила дорогу голубю и инспектор нажал по тормозам. Ваша очередь 👇",
    status: "draft"
  }
];

// Read existing queue if any
try {
  let existing = execSync('npx wrangler kv:key get threads_queue --binding INSTALLS', { encoding: 'utf-8' });
  if (existing && existing.trim()) {
    const q = JSON.parse(existing);
    // Overwrite for simplicity in this script, or append. We will just overwrite to initialize it cleanly.
  }
} catch (e) {
  // Key might not exist, which is fine.
}

const payload = JSON.stringify(posts);
require('fs').writeFileSync('threads_payload.json', payload);

// Upload to KV
console.log("Uploading to KV...");
execSync('npx wrangler kv:key put threads_queue --binding INSTALLS --path threads_payload.json', { stdio: 'inherit' });
console.log("Done!");
