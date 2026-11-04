from apps.common.exceptions import ApiError


class PaymentError(ApiError):
    def __init__(self, status: int, message: str):
        super().__init__(message, status)
        self.status = status
