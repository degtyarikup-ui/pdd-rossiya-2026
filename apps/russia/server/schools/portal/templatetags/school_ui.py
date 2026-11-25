from django import template
from django.utils.html import format_html
from portal.student_links import student_app_link

register = template.Library()
register.simple_tag(student_app_link)


@register.simple_tag
def icon(name):
    return format_html(
        '<svg class="icon" aria-hidden="true" focusable="false"><use href="/assets/schools/icons.svg#{}"></use></svg>',
        name,
    )


@register.filter
def initials(name):
    words = name.strip().split()
    return "".join(w[0] for w in words[:2]).upper()
