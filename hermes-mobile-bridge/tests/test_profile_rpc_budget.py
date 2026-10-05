"""A slow native clone must finish before configuration/read-back can follow."""
import asyncio

import pytest

from hermes_mobile_bridge.upstream import Backend
from hermes_mobile_bridge.core import Problem


@pytest.mark.asyncio
async def test_profile_clone_has_more_time_without_retrying_an_uncertain_rpc(monkeypatch):
    async def no_event(*args):
        pass

    backend = Backend('default', {}, no_event, no_event)
    calls = []
    budgets = []

    class Socket:
        closed = False

        async def send_json(self, request):
            calls.append(request['method'])

    backend.ws = Socket()

    async def expire(future, timeout):
        budgets.append(timeout)
        raise asyncio.TimeoutError()

    monkeypatch.setattr(asyncio, 'wait_for', expire)
    for method in ('profiles.create', 'profiles.configure', 'profiles.list'):
        with pytest.raises(Problem) as result:
            await backend.rpc(method, {'name': 'temporary-test'})
        assert result.value.code == 'upstream_uncertain'
        assert not backend.pending
    assert budgets == [60, 30, 30]
    assert calls == ['profiles.create', 'profiles.configure', 'profiles.list']
