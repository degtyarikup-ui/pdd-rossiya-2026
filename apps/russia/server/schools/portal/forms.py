from django import forms

from .models import Employee

TERMS_VERSION = "pilot-2026-11-24"


class TermsForm(forms.Form):
    name = forms.CharField(
        label="Ваше имя",
        max_length=100,
        widget=forms.TextInput(attrs={"autocomplete": "name"}),
    )
    terms = forms.BooleanField(label="Принимаю условия тестового кабинета")


class SchoolForm(TermsForm):
    school = forms.CharField(label="Название школы или кабинета", max_length=100)
    field_order = ["school", "name", "terms"]


class GroupForm(forms.Form):
    name = forms.CharField(
        label="Название группы",
        max_length=90,
        widget=forms.TextInput(attrs={"placeholder": "Например, Вечерняя Б-12"}),
    )
    instructor = forms.ModelChoiceField(
        label="Преподаватель", queryset=Employee.objects.none(), empty_label=None
    )

    def __init__(self, *args, employee, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["instructor"].queryset = employee.school.staff.filter(
            active=True
        ).order_by("name")
        if not employee.manager:
            del self.fields["instructor"]


class InviteForm(forms.Form):
    email = forms.EmailField(
        label="Почта инструктора",
        max_length=254,
        widget=forms.EmailInput(attrs={"autocomplete": "email"}),
    )


class RenameSchoolForm(forms.Form):
    school = forms.CharField(label="Название школы", max_length=100)
