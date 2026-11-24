import secrets

from allauth.account.models import EmailAddress
from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from portal.forms import TERMS_VERSION
from portal.models import Employee, Group, Learner, School


class Command(BaseCommand):
    help = "Создать две вымышленные школы в локальном кабинете"

    @transaction.atomic
    def handle(self, *args, **options):
        if not settings.LOCAL:
            raise CommandError("Команда доступна только в локальном режиме.")
        access = settings.STATE / "demo-access.txt"
        if access.exists():
            self.stdout.write(f"Тестовые аккаунты уже созданы. Доступы: {access}")
            return
        lines = []
        for school_name, slug in [
            ("Автошкола «Старт»", "start"),
            ("Автошкола «Вектор»", "vector"),
        ]:
            school = School.objects.create(name=school_name)
            members = []
            for prefix, name, role in [
                ("director", "Анна Соколова", Employee.Role.MANAGER),
                ("instructor", "Михаил Орлов", Employee.Role.INSTRUCTOR),
                ("teacher", "Ирина Белова", Employee.Role.INSTRUCTOR),
            ]:
                address = f"{prefix}@{slug}.example.test"
                pw = secrets.token_urlsafe(18)
                user = get_user_model().objects.create_user(
                    username=address, email=address, password=pw
                )
                EmailAddress.objects.create(
                    user=user, email=address, primary=True, verified=True
                )
                member = Employee.objects.create(
                    school=school,
                    user=user,
                    name=name,
                    role=role,
                    terms_version=TERMS_VERSION,
                )
                members.append(member)
                lines.append(f"{school.name} · {role.label}\n{address}\n{pw}\n")
            for group_name, instructor, names in [
                ("Выходной день · Б-10", members[2], ["Глеб Лисов", "Лидия Мишина"]),
                ("Утренняя · Б-11", members[0], []),
                (
                    "Вечерняя · Б-12",
                    members[1],
                    ["Алиса Рябова", "Борис Лукин", "Дина Степанова"],
                ),
            ]:
                group = Group.objects.create(name=group_name, instructor=instructor)
                Learner.objects.bulk_create(
                    [Learner(group=group, name=name) for name in names]
                )
        with access.open("x") as f:
            access.chmod(0o600)
            f.write("\n".join(lines))
        self.stdout.write(f"Школы созданы. Тестовые логины и пароли: {access}")
