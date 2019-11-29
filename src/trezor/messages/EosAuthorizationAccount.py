# Automatically generated by pb2py
# fmt: off
import protobuf as p

from .EosPermissionLevel import EosPermissionLevel

if __debug__:
    try:
        from typing import Dict, List, Optional
        from typing_extensions import Literal  # noqa: F401
    except ImportError:
        Dict, List, Optional = None, None, None  # type: ignore


class EosAuthorizationAccount(p.MessageType):

    def __init__(
        self,
        account: EosPermissionLevel = None,
        weight: int = None,
    ) -> None:
        self.account = account
        self.weight = weight

    @classmethod
    def get_fields(cls) -> Dict:
        return {
            1: ('account', EosPermissionLevel, 0),
            2: ('weight', p.UVarintType, 0),
        }