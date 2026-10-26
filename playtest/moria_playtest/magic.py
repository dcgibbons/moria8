"""Prayers (M5b, docs/AI_PLAYTEST_DESIGN.md §16): the cast layer.

Only what the goals need (maintainer decision §16.4 item 3): healing, fear,
finding the way out, and food, added as the traces call for them.

The game's flow (core/player_magic.s): ``P`` asks "Prayer book (a-v)?", then
"Pray which? (a-c, ESC)"; ``?`` there shows the list of known prayers with
their mana and level, and a letter prays one. ``F`` asks "Study which book
(a-v)?" and a priest learns a random prayer it is ready for from that book
("You learn from the book!", or "No new spells to learn.").

Books bind a caster (maintainer, 2026-10-25): a prayer is learned from, and
prayed from, the book that holds it, so the bot studies each book it carries
and prays through the right one. The book prompt letters only the prayer
books carried, in pack order (``piw_pick_filtered_inv_key``), and a new book
lands in the first empty pack slot (``inv_add_item``), so with more than one
book the bot reads their order from the prompt's ``?`` list.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from .game import Mode, Observation

KEY_PRAY, KEY_STUDY, KEY_LIST, KEY_ESC = ord("P"), ord("F"), ord("?"), 0x1B
STATUS_MP = re.compile(r"MP:\s*(\d+)/(\d+)")
LIST_ROW = re.compile(r"^ ([a-z])\) (.+?)\s+(\d+)\s+(\d+)\s*$")   # " b) Cure Light Wounds   2    1"
BOOK_RANGE = re.compile(r"\(a-([a-v])\)")
PACK_ROW = re.compile(r"^\s*([a-v])\) (?:\d+ )?(\S.*?)\s*$")

CURE_LIGHT, CURE_MEDIUM = "Cure Light Wounds", "Cure Medium Wounds"
REMOVE_FEAR, DETECT_DOORS, CREATE_FOOD = "Remove Fear", "Detect Doors/Stairs", "Create Food"
HEALS = (CURE_MEDIUM, CURE_LIGHT)   # best first
PORTAL, SANCTUARY = "Portal", "Sanctuary"                 # escapes (Words of Wisdom)
BLIND, CHANT, ORB = "Blind Creature", "Chant", "Orb of Draining"   # control, Bless x2, attack

# The prayer books in order (core/item_tables.s itn_48, itn_58-60), and the
# character level of each book's first prayer for a Priest and a Paladin
# (docs/FEATURE_MAP.md §7.3): a book is worth buying from then on.
PRAYER_BOOKS = ("Beginners Handbook", "Words of Wisdom", "Chants and Blessings", "Exorcism")
BOOK_LEVELS = {"priest": (1, 5, 9, 15), "paladin": (1, 9, 15, 29)}
FIRST_BOOK = PRAYER_BOOKS[0]   # every Priest and Paladin starts with it (core/player_create.s)
# The store and pack show "Holy Book of Prayers <title>", cut to the line's
# width: "Holy Book of Prayers Words" at the C64 Temple (M5b round 22, seed
# 1003 replay: no book was ever bought under the bare title).
BOOK_PREFIX = "Holy Book of Prayers "


def store_name(book: str) -> str:
    """The shortest start of a book's shown name that tells it apart."""
    return BOOK_PREFIX + book.split()[0][:5]


def book_of(name: str) -> str | None:
    """The prayer book a store or pack line names, full or cut short."""
    for book in PRAYER_BOOKS:
        full = BOOK_PREFIX + book
        if book in name or (name.startswith(store_name(book)) and full.startswith(name.rstrip())):
            return book
    return None


@dataclass(frozen=True)
class Prayer:
    letter: str
    mana: int
    level: int
    book: str = FIRST_BOOK


class Magic:
    """What the character knows, the books it carries, and the prayer in progress."""

    def __init__(self) -> None:
        self.known: dict[str, Prayer] = {}
        self.books: list[str] | None = None   # prayer books in book-prompt order; None: unknown
        self.listing_books = False            # the book prompt's "?" list is open
        self.listed_books: set[str] = set()   # books whose prayer list has been read
        self.listed = False                   # every carried book's list read since the last change
        self.current: str | None = None       # the book chosen at the last book prompt
        self.reading: str | None = None       # the book whose list the open P flow reads
        self.wanted: str | None = None        # the prayer the open P flow is for ("" = read a list only)
        self.studying = False
        self.study_due = True                 # a level-up (or a new character) may have a prayer to learn
        self.study_book: str | None = None    # the book the open F flow chose
        self.study_done: set[str] = set()     # books with nothing to learn until the next level
        self.last: str | None = None          # the prayer last prayed, for the game's answer
        self.refused: set[str] = set()        # refused without a turn: not again until the next level

    @staticmethod
    def mana(obs: Observation) -> tuple[int, int]:
        match = STATUS_MP.search(obs.rows[23])
        return (int(match.group(1)), int(match.group(2))) if match else (0, 0)

    def caster(self, obs: Observation) -> bool:
        return self.mana(obs)[1] > 0

    def feeds(self, obs: Observation) -> bool:
        """Create Food known and within the character's maximum mana: food
        need not send it back to town (M5b round 34: a level-9 Dwarf Priest
        made 191 town trips for 1-3 rations each)."""
        prayer = self.known.get(CREATE_FOOD)
        return (prayer is not None and CREATE_FOOD not in self.refused and prayer.level <= obs.clvl
                and prayer.mana <= self.mana(obs)[1])

    def can(self, obs: Observation, name: str) -> bool:
        prayer = self.known.get(name)
        return (prayer is not None and name not in self.refused and prayer.level <= obs.clvl
                and prayer.mana <= self.mana(obs)[0])

    def new_book(self) -> None:
        """A book bought: learn the pack order again, then study and read it."""
        self.books, self.listed, self.study_due = None, False, True
        self.study_done.clear()

    def note(self, messages: str) -> None:
        if "Welcome to level" in messages:
            self.study_due = True
            self.study_done.clear()
            self.refused.clear()
        if self.last and ("You're not experienced enough." in messages or "You faint from fatigue." in messages
                          or "You don't know that spell." in messages):
            # No turn passes: trying again would repeat forever.
            self.refused.add(self.last)
            self.last = None
        if self.reading is not None and "You don't know that spell." in messages:
            # Nothing learned from this book yet: its list cannot be shown.
            # Read again once a prayer is learned from it (M5b round 23: a
            # new Words of Wisdom was asked for 1,500 times in town).
            self.listed_books.add(self.reading)
            self.listed = self.books is not None and all(b in self.listed_books for b in self.books)
        self.reading = None
        if "You learn from the book!" in messages:
            if self.study_book is not None:
                self.listed_books.discard(self.study_book)   # a new prayer there: read its list again
            self.listed = False
            self.study_due = True    # perhaps another
            self.study_book = None
        if "No new spells to learn." in messages:
            if self.study_book is not None:
                # Nothing more in this book: the next one, if any.
                self.study_done.add(self.study_book)
                self.study_due = self.books is None or any(b not in self.study_done for b in self.books)
            else:
                self.study_due = False   # nothing to learn at all: no book was asked for
            self.study_book = None

    def spare(self, obs: Observation, name: str) -> bool:
        """``name`` can be prayed and still leave the mana for the best heal
        known: a level-1 Priest's Bless spent the 2 mana its only heal
        needed (M5b round 16)."""
        if not self.can(obs, name):
            return False
        heal = next((self.known[h].mana for h in HEALS if h in self.known and self.known[h].level <= obs.clvl), 0)
        return self.mana(obs)[0] - self.known[name].mana >= heal

    def pray(self, name: str, why: str) -> tuple[int, str, str]:
        self.wanted = name
        return KEY_PRAY, "pray", why

    def study(self) -> tuple[int, str, str]:
        self.studying, self.study_book = True, None
        return KEY_STUDY, "pray", "study the prayer books"

    def read_list(self) -> tuple[int, str, str]:
        return self.pray("", "read the prayer list")

    def target_book(self) -> str | None:
        """The book the flow in progress needs."""
        books = self.books or []
        if self.studying:
            # The latest book first: each level-up's new prayers went to the
            # Beginners Handbook's leftovers, and Priests with Words of
            # Wisdom died at level 7-10 praying Cure Light Wounds, never
            # having learned Cure Medium Wounds or Portal (M5b round 35).
            left = [b for b in books if b not in self.study_done]
            return max(left, key=lambda b: PRAYER_BOOKS.index(b) if b in PRAYER_BOOKS else -1, default=None)
        if self.wanted == "":
            return next((b for b in books if b not in self.listed_books), None)
        prayer = self.known.get(self.wanted or "")
        return prayer.book if prayer is not None and prayer.book in books else None

    def choose_book(self, letter_of: dict[str, str]) -> tuple[int, str, str]:
        book = self.target_book()
        studying, self.studying = self.studying, False
        if book is None:
            if self.wanted:
                # Known, but in no book the prompt offers: not again this
                # level, and the books are listed again (M5b round 23b: a
                # Priest that picked up books asked for Portal 2,500 times).
                self.refused.add(self.wanted)
                self.books = None
            self.wanted = None
            return KEY_ESC, "prompt", "no book wanted: cancel"
        self.current = book
        self.reading = book if self.wanted == "" else None
        if studying:
            self.study_book = book
        return ord(letter_of[book].upper()), "prompt", f"the book {book}"

    def book_list(self, obs: Observation) -> tuple[int, str, str]:
        """The book prompt's "?" list: the books carried, in prompt order."""
        letters: dict[str, str] = {}
        order: list[str] = []
        for row in obs.rows[1:23]:
            match = PACK_ROW.match(row)
            if match:
                name = book_of(match.group(2)) or match.group(2)
                letters[name] = match.group(1)
                order.append(name)
        self.listing_books = False
        if not order:
            self.studying, self.wanted = False, None
            return KEY_ESC, "prompt", "no prayer book listed: cancel"
        if self.books is not None and any(b not in self.books for b in order):
            self.study_due = True   # a book picked up: something to learn there, perhaps
            self.study_done.clear()
        self.books = order
        self.listed = all(b in self.listed_books for b in order)
        return self.choose_book(letters)

    def prompt(self, obs: Observation) -> tuple[int, str, str]:
        """Answer the book, prayer and list prompts of the flow in progress."""
        if obs.stage == "book":
            if self.wanted is None and not self.studying:
                return KEY_ESC, "prompt", "no prayer wanted: cancel"
            match = BOOK_RANGE.search(obs.rows[0])
            count = ord(match.group(1)) - ord("a") + 1 if match else 1
            if self.books is None or len(self.books) != count:
                if count == 1:
                    self.books = [FIRST_BOOK]   # the starting book: no list needed
                    self.listed = FIRST_BOOK in self.listed_books
                else:
                    self.listing_books = True
                    return KEY_LIST, "prompt", "list the prayer books"
            return self.choose_book({b: chr(ord("a") + i) for i, b in enumerate(self.books)})
        book = self.current or FIRST_BOOK
        if obs.stage == "list":
            for row in obs.rows[2:23]:
                match = LIST_ROW.match(row)
                if match:
                    self.known[match.group(2)] = Prayer(match.group(1), int(match.group(3)), int(match.group(4)), book)
            self.listed_books.add(book)
            self.listed = self.books is not None and all(b in self.listed_books for b in self.books)
        wanted, prayer = self.wanted, self.known.get(self.wanted or "")
        if obs.stage == "which" and book not in self.listed_books:
            return KEY_LIST, "prompt", "show the prayer list"
        self.wanted = None
        if prayer is None or not wanted or prayer.book != book:
            return KEY_ESC, "prompt", "the prayer list is read" if book in self.listed_books else "prayer not known: cancel"
        self.last = wanted
        return ord(prayer.letter.upper()), "prompt", f"pray {wanted}"


def handles(obs: Observation) -> bool:
    return obs.mode == Mode.SPELL
