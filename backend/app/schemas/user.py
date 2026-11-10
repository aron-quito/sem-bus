from typing import Optional
from pydantic import BaseModel


class UserProfileResponse(BaseModel):
    id: str
    phone: str
    name: Optional[str] = None
    role: str
    points_balance: int = 0
    is_active: bool = True
