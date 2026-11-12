"""The reversed rule (workflows 2 and 3): a line whose reference matches no ticket goes on the one open ticket with the
same phone and amount from the last ten minutes; if more than one fits, it goes to suspense. Typed references still land."""
import unittest

from matatu.clock import FixedClock
from matatu.models import TICKET_ISSUED, TICKET_PAID, StatementLine, Ticket
from matatu.payments.reconcile import reconcile_statement
from matatu.payments.suspense import pending_suspense
from matatu.store.memory import InMemoryStore
from matatu.store.repositories import save_ticket


def store_with(*tickets):
    store = InMemoryStore()
    for identifier, phone in tickets:
        save_ticket(store, Ticket(id=identifier, trip_id="TR1", route_id="46", vehicle_id="V1", from_stage="KAW",
                                  to_stage="CBD", phone=phone, fare_kes=80, issued_at=1000))
    return store


class Reversed(unittest.TestCase):
    def test_one_ticket_with_that_phone_and_amount_is_paid(self):
        store = store_with(("TKT-2345AB", "+254700000001"), ("TKT-2345AC", "+254700000002"))
        reconcile_statement(store, [StatementLine(code="QA1", phone="+254700000001", amount_kes=80, account_ref="FARE", at=1100)], FixedClock())
        self.assertEqual(store.tickets["TKT-2345AB"].status, TICKET_PAID)

    def test_two_tickets_with_that_phone_and_amount_go_to_suspense(self):
        store = store_with(("TKT-2345AB", "+254700000001"), ("TKT-2345AC", "+254700000001"))
        reconcile_statement(store, [StatementLine(code="QA1", phone="+254700000001", amount_kes=80, account_ref="FARE", at=1100)], FixedClock())
        self.assertEqual(store.tickets["TKT-2345AB"].status, TICKET_ISSUED)
        self.assertEqual(store.tickets["TKT-2345AC"].status, TICKET_ISSUED)
        self.assertEqual([item.reason for item in pending_suspense(store)], ["unknown reference"])
