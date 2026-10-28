from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.context import current_device, current_location

from . import services


class PushView(APIView):
    def post(self, request):
        results = services.push(request.user, request.data.get("operations"),
                                location=current_location(request), device=current_device(request))
        return Response({"results": results})


class PullView(APIView):
    def get(self, request):
        return Response(services.pull(request.user, request.query_params.get("since")))
