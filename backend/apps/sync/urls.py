from django.urls import path

from . import views

urlpatterns = [
    path("sync/push", views.PushView.as_view()),
    path("sync/pull", views.PullView.as_view()),
]
