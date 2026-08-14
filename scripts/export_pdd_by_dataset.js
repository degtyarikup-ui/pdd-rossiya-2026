#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SOURCE_DIR = path.join(ROOT, 'assets', 'countries', 'ru', 'questions');
const OUT_DIR = path.join(ROOT, 'exports', 'pdd-by');

const SOURCES = [
  { key: 'AB', ticketsFile: 'questions_ab.json', topicsFile: 'topics_ab.json' },
  { key: 'CD', ticketsFile: 'questions_cd.json', topicsFile: 'topics_cd.json' },
];

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function normalizeAnswer(answer, index) {
  return {
    index: index + 1,
    text: String(answer.text ?? '').trim(),
    correct: Boolean(answer.correct),
  };
}

function normalizeQuestion(question, categoryKey) {
  const answers = (question.answers || []).map(normalizeAnswer);
  const correctIndex = answers.findIndex((answer) => answer.correct);
  const correctAnswer = correctIndex >= 0 ? answers[correctIndex] : null;

  return {
    id: String(question.id ?? ''),
    category: categoryKey,
    ticketNumber: Number(question.ticketNumber ?? 0) || 0,
    question: String(question.question ?? '').trim(),
    answers,
    correctAnswerIndex: correctIndex >= 0 ? correctIndex + 1 : null,
    correctAnswerText: correctAnswer ? correctAnswer.text : '',
    comment: String(question.comment ?? '').trim(),
    image: question.image ?? null,
    pddPoints: Array.isArray(question.pddPoints) ? question.pddPoints : [],
    topic: Array.isArray(question.topic) ? question.topic.filter(Boolean) : [],
  };
}

function addUnique(list, value) {
  if (!value) return;
  if (!list.includes(value)) list.push(value);
}

function mergeUnique(target, values) {
  for (const value of values || []) addUnique(target, value);
}

function collectCategory(categoryKey, ticketsData, topicsData) {
  const questionsById = new Map();
  const ticketGroups = [];
  const topicGroups = [];

  for (const ticket of ticketsData.tickets || []) {
    const ticketNumber = Number(ticket.number);
    const questionIds = [];

    for (const question of ticket.questions || []) {
      const normalized = normalizeQuestion(question, categoryKey);
      questionIds.push(normalized.id);

      const existing = questionsById.get(normalized.id);
      if (!existing) {
        questionsById.set(normalized.id, {
          ...normalized,
          appearances: [{ ticketNumber, position: questionIds.length }],
          topics: [...normalized.topic],
        });
      } else {
        existing.appearances.push({ ticketNumber, position: questionIds.length });
        for (const topicName of normalized.topic) addUnique(existing.topics, topicName);
        if (!existing.image && normalized.image) existing.image = normalized.image;
        if (!existing.comment && normalized.comment) existing.comment = normalized.comment;
        if ((!existing.answers || existing.answers.length === 0) && normalized.answers.length > 0) {
          existing.answers = normalized.answers;
          existing.correctAnswerIndex = normalized.correctAnswerIndex;
          existing.correctAnswerText = normalized.correctAnswerText;
        }
      }
    }

    ticketGroups.push({
      number: ticketNumber,
      questionIds,
    });
  }

  for (const topic of topicsData.topics || []) {
    const questionIds = [];
    for (const question of topic.questions || []) {
      const normalized = normalizeQuestion(question, categoryKey);
      questionIds.push(normalized.id);
      const existing = questionsById.get(normalized.id);
      if (!existing) {
        questionsById.set(normalized.id, {
          ...normalized,
          appearances: [],
          topics: [...normalized.topic, topic.name],
        });
      } else {
        addUnique(existing.topics, topic.name);
        if (!existing.image && normalized.image) existing.image = normalized.image;
        if (!existing.comment && normalized.comment) existing.comment = normalized.comment;
        if ((!existing.answers || existing.answers.length === 0) && normalized.answers.length > 0) {
          existing.answers = normalized.answers;
          existing.correctAnswerIndex = normalized.correctAnswerIndex;
          existing.correctAnswerText = normalized.correctAnswerText;
        }
      }
    }

    topicGroups.push({
      name: topic.name,
      questionIds,
    });
  }

  const questions = [...questionsById.values()].sort((a, b) => {
    const ticketA = a.ticketNumber || Number.MAX_SAFE_INTEGER;
    const ticketB = b.ticketNumber || Number.MAX_SAFE_INTEGER;
    if (ticketA !== ticketB) return ticketA - ticketB;
    return a.id.localeCompare(b.id);
  });

  return {
    category: categoryKey,
    ticketCount: ticketGroups.length,
    questionCount: ticketsData.tickets.reduce((acc, ticket) => acc + (ticket.questions || []).length, 0),
    uniqueQuestionCount: questions.length,
    ticketGroups,
    topicGroups,
    questions,
  };
}

function toCsvValue(value) {
  const text = value == null ? '' : String(value).replace(/\r?\n|\r/g, ' ');
  return `"${text.replace(/"/g, '""')}"`;
}

function collectMasterQuestions(categories) {
  const byId = new Map();

  for (const category of categories) {
    for (const question of category.questions) {
      const existing = byId.get(question.id);
      if (!existing) {
        byId.set(question.id, {
          id: question.id,
          question: question.question,
          answers: question.answers,
          correctAnswerIndex: question.correctAnswerIndex,
          correctAnswerText: question.correctAnswerText,
          comment: question.comment,
          image: question.image,
          pddPoints: question.pddPoints,
          topics: [...(question.topics || [])],
          categories: [category.category],
          appearances: (question.appearances || []).map((appearance) => ({
            category: category.category,
            ticketNumber: appearance.ticketNumber,
            position: appearance.position,
          })),
        });
        continue;
      }

      addUnique(existing.categories, category.category);
      mergeUnique(existing.topics, question.topics);
      if (!existing.question && question.question) existing.question = question.question;
      if ((!existing.answers || existing.answers.length === 0) && question.answers.length > 0) {
        existing.answers = question.answers;
        existing.correctAnswerIndex = question.correctAnswerIndex;
        existing.correctAnswerText = question.correctAnswerText;
      }
      if (!existing.comment && question.comment) existing.comment = question.comment;
      if (!existing.image && question.image) existing.image = question.image;
      if ((!existing.pddPoints || existing.pddPoints.length === 0) && question.pddPoints.length > 0) {
        existing.pddPoints = question.pddPoints;
      }
      existing.appearances.push(
        ...(question.appearances || []).map((appearance) => ({
          category: category.category,
          ticketNumber: appearance.ticketNumber,
          position: appearance.position,
        })),
      );
    }
  }

  return [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
}

function buildCsv(categories) {
  const header = [
    'category',
    'question_id',
    'ticket_number',
    'question_index',
    'topics',
    'correct_answer_index',
    'correct_answer_text',
    'question',
    'answer_1',
    'answer_2',
    'answer_3',
    'answer_4',
    'answer_5',
    'comment',
    'image',
  ];

  const rows = [header.map(toCsvValue).join(',')];

  for (const category of categories) {
    for (const question of category.questions) {
      const answers = question.answers || [];
      rows.push([
        category.category,
        question.id,
        question.ticketNumber,
        question.appearances && question.appearances.length ? question.appearances[0].position : '',
        (question.topics || []).join(' | '),
        question.correctAnswerIndex,
        question.correctAnswerText,
        question.question,
        answers[0]?.text ?? '',
        answers[1]?.text ?? '',
        answers[2]?.text ?? '',
        answers[3]?.text ?? '',
        answers[4]?.text ?? '',
        question.comment ?? '',
        question.image ?? '',
      ].map(toCsvValue).join(','));
    }
  }

  return rows.join('\n') + '\n';
}

function buildMasterCsv(questions) {
  const header = [
    'question_id',
    'categories',
    'ticket_occurrences',
    'topics',
    'correct_answer_index',
    'correct_answer_text',
    'question',
    'answer_1',
    'answer_2',
    'answer_3',
    'answer_4',
    'answer_5',
    'comment',
    'image',
  ];

  const rows = [header.map(toCsvValue).join(',')];

  for (const question of questions) {
    const answers = question.answers || [];
    const occurrences = (question.appearances || [])
      .map((item) => `${item.category}:${item.ticketNumber}.${item.position}`)
      .join(' | ');
    rows.push([
      question.id,
      (question.categories || []).join(' | '),
      occurrences,
      (question.topics || []).join(' | '),
      question.correctAnswerIndex,
      question.correctAnswerText,
      question.question,
      answers[0]?.text ?? '',
      answers[1]?.text ?? '',
      answers[2]?.text ?? '',
      answers[3]?.text ?? '',
      answers[4]?.text ?? '',
      question.comment ?? '',
      question.image ?? '',
    ].map(toCsvValue).join(','));
  }

  return rows.join('\n') + '\n';
}

function buildMarkdown(categories) {
  const lines = [];
  lines.push('# ПДД Беларусь');
  lines.push('');
  lines.push('Нормализованная выгрузка вопросов по категориям `AB` и `CD`.');
  lines.push('');

  for (const category of categories) {
    lines.push(`## ${category.category}`);
    lines.push('');
    lines.push(`- Билетов: ${category.ticketCount}`);
    lines.push(`- Вопросов в билетах: ${category.questionCount}`);
    lines.push(`- Уникальных вопросов: ${category.uniqueQuestionCount}`);
    lines.push('');
    lines.push('### Темы');
    lines.push('');
    for (const topic of category.topicGroups) {
      lines.push(`- ${topic.name}: ${topic.questionIds.length}`);
    }
    lines.push('');
  }

  const masterQuestions = collectMasterQuestions(categories);
  lines.push('## ALL');
  lines.push('');
  lines.push(`- Уникальных вопросов по всем категориям: ${masterQuestions.length}`);
  lines.push('');

  return lines.join('\n');
}

function main() {
  ensureDir(OUT_DIR);

  const categories = SOURCES.map((source) => {
    const ticketsData = readJson(path.join(SOURCE_DIR, source.ticketsFile));
    const topicsData = readJson(path.join(SOURCE_DIR, source.topicsFile));
    return collectCategory(source.key, ticketsData, topicsData);
  });
  const masterQuestions = collectMasterQuestions(categories);

  const payload = {
    source: 'pdd.by',
    generatedAt: new Date().toISOString(),
    categories,
    allQuestions: masterQuestions,
  };

  fs.writeFileSync(
    path.join(OUT_DIR, 'pdd-by-belarus-questions.normalized.json'),
    JSON.stringify(payload, null, 2) + '\n',
    'utf8',
  );
  fs.writeFileSync(
    path.join(OUT_DIR, 'pdd-by-belarus-questions.by-category.csv'),
    buildCsv(categories),
    'utf8',
  );
  fs.writeFileSync(
    path.join(OUT_DIR, 'pdd-by-belarus-questions.master.csv'),
    buildMasterCsv(masterQuestions),
    'utf8',
  );
  fs.writeFileSync(
    path.join(OUT_DIR, 'README.md'),
    buildMarkdown(categories) + '\n',
    'utf8',
  );

  const summary = categories.map((category) => ({
    category: category.category,
    tickets: category.ticketCount,
    questions: category.questionCount,
    unique: category.uniqueQuestionCount,
  }));
  console.log(JSON.stringify({ outDir: OUT_DIR, summary, masterUnique: masterQuestions.length }, null, 2));
}

main();
