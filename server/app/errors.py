class ApiError(Exception):
    """An error the client is allowed to see. Becomes a JSON response."""

    def __init__(self, status: int, code: str, message: str, **extra):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.extra = extra

    def to_json(self) -> dict:
        return {"error": self.code, "message": self.message, **self.extra}


def bad_request(code: str, message: str, **extra) -> ApiError:
    return ApiError(400, code, message, **extra)
