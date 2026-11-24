from django.core.management import call_command
from django.db import migrations


def create_cache(apps, schema_editor):
    call_command(
        "createcachetable", database=schema_editor.connection.alias, verbosity=0
    )


class Migration(migrations.Migration):
    dependencies = [("portal", "0001_initial")]
    operations = [migrations.RunPython(create_cache, migrations.RunPython.noop)]
