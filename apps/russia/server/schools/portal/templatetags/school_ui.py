from django import template
from django.utils.html import format_html

register = template.Library()


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
