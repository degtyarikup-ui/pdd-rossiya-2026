# PDD workspace

- Россия: [apps/russia](apps/russia/), документация: [карта](apps/russia/docs/README.md).
- Общий интерфейс: [packages/pdd_ui](packages/pdd_ui/).
- План миграции: [docs/architecture/multi-app-migration.md](docs/architecture/multi-app-migration.md).

```sh
flutter pub get
cd apps/russia
flutter analyze
flutter test
```

Из корня по-прежнему работают `./scripts/build_dev.sh --arm64`,
`./scripts/build.sh ru web`, `./scripts/network_editor.sh`.
`build/` на этом ноутбуке — совместимая ссылка на российские артефакты.
Свежая копия хранит их в `apps/russia/build/`.
