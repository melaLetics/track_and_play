# -*- coding: utf-8 -*-
"""
Konvertiert einen mtg_stats-Datenabzug (export_2026-09-07.json) in das
ExportBundle-Format von Track & Play, damit er ueber den bestehenden
Import-Assistenten ("Daten importieren" in den Weiteren Optionen)
eingelesen werden kann.

Deck-Verleih: Spielt ein Teilnehmer laut Quelldaten ein Deck, das laut
Deck-Liste tatsaechlich einem ANDEREN Spieler gehoert, wird das jetzt
(seit die App echten Deck-Verleih unterstuetzt) korrekt verlinkt statt
nur als Notiz vermerkt: deckName bleibt das gespielte Deck,
deckOwnerName wird auf den tatsaechlichen Besitzer gesetzt (siehe
GameParticipantExport.deckOwnerName / ImportService).
"""
import json
import io
from datetime import datetime

SRC = "export_2026-09-07.json"
DST = "mtg_stats_import_2026-09-07.json"

WUBRG_ORDER = "WUBRG"
COLOR_NAME_TO_LETTER = {"White": "W", "Blue": "U", "Black": "B", "Red": "R", "Green": "G"}

MODE_MAP = {
    "Commander": "commander", "EDH": "commander",
    "cEDH": "competitiveCommander", "Competitive Commander": "competitiveCommander",
    "Two-Headed Giant": "twoHeadedGiant", "2HG": "twoHeadedGiant",
    "Archenemy": "archenemy",
}


def convert_color_identity(names):
    letters = [COLOR_NAME_TO_LETTER[n] for n in names]
    letters.sort(key=lambda c: WUBRG_ORDER.index(c))
    return "".join(letters)


def main():
    with io.open(SRC, encoding="utf-8") as f:
        src = json.load(f)

    players_out = [{"name": p["name"], "archived": False} for p in src["players"]]

    decks_by_owner_name = {}
    decks_by_name_only = {}
    decks_out = []
    for d in src["decks"]:
        color_identity = convert_color_identity(d["colorIdentity"])
        entry = {
            "ownerName": d["owner"], "name": d["name"], "colorIdentity": color_identity,
            "commanderName": d["commander"] or None, "secondCommanderName": d["commander2"] or None,
            "buildType": d["type"], "bracket": d["bracket"], "isProxy": False,
            "isTournamentLegal": True, "deckLink": d["decklink"] or None,
            "archived": not d.get("active", True),
        }
        decks_out.append(entry)
        decks_by_owner_name[(d["owner"].lower(), d["name"].lower())] = d
        decks_by_name_only.setdefault(d["name"].lower(), d)

    participants_by_game = {}
    for p in src["participants"]:
        participants_by_game.setdefault(p["gameId"], []).append(p)

    games_out = []
    lending_games_count = 0
    lending_cases_count = 0
    unresolved_lending_cases = []
    unmapped_modes = set()

    for g in src["games"]:
        mode_raw = g["mode"]
        mode = MODE_MAP.get(mode_raw)
        if mode is None:
            unmapped_modes.add(mode_raw)
            continue

        parts_src = sorted(participants_by_game.get(g["id"], []), key=lambda p: p["id"])
        participants_out = []
        game_has_lending = False

        for p in parts_src:
            player_name = p["player"]
            deck_name = p["deck"]
            owner_key = (player_name.lower(), deck_name.lower())
            owned_deck = decks_by_owner_name.get(owner_key)

            deck_owner_name = None
            if owned_deck is not None:
                color_identity = convert_color_identity(owned_deck["colorIdentity"])
            else:
                # Deck-Verleih: das Deck gehoert laut Deck-Liste einem
                # ANDEREN Spieler - jetzt korrekt verlinkt statt
                # gedroppt (siehe Docstring oben).
                fallback_deck = decks_by_name_only.get(deck_name.lower())
                if fallback_deck is not None:
                    color_identity = convert_color_identity(fallback_deck["colorIdentity"])
                    deck_owner_name = fallback_deck["owner"]
                    game_has_lending = True
                    lending_cases_count += 1
                else:
                    # Deck taucht in der Deck-Liste ueberhaupt nicht auf -
                    # kann laut bisheriger Analyse nicht vorkommen, aber
                    # zur Sicherheit sauber behandelt statt eine
                    # KeyError zu riskieren.
                    color_identity = ""
                    unresolved_lending_cases.append((g["id"], player_name, deck_name))

            team = None
            start_position = p["startPosition"]
            if mode == "twoHeadedGiant":
                team = "A" if p["startPosition"] == 1 else "B" if p["startPosition"] == 2 else str(p["startPosition"])
                start_position = None

            participants_out.append({
                "playerName": player_name,
                "deckName": deck_name if (owned_deck is not None or deck_owner_name is not None) else None,
                "deckOwnerName": deck_owner_name,
                "anonymousLabel": None, "anonymousColorIdentity": None,
                "colorIdentity": color_identity, "isWinner": bool(p["won"]),
                "placement": p.get("placement"), "team": team,
                "startingLife": None, "startPosition": start_position,
            })

        if game_has_lending:
            lending_games_count += 1

        games_out.append({
            "playedAt": g["date"], "mode": mode, "notes": None, "groupName": None,
            "entryMode": "manual", "durationSeconds": None,
            "isDraw": bool(g.get("draw", False)), "participants": participants_out,
            "firstBloodParticipantIndex": None,
        })

    if unmapped_modes:
        raise SystemExit(f"Unbekannte Spielmodi, bitte MODE_MAP ergaenzen: {unmapped_modes}")

    bundle = {
        "schemaVersion": 1, "exportedAt": datetime.now().isoformat(),
        "players": players_out, "decks": decks_out, "groups": [], "games": games_out,
    }

    with io.open(DST, "w", encoding="utf-8") as f:
        json.dump(bundle, f, ensure_ascii=False, indent=2)

    print(f"Spieler: {len(players_out)}")
    print(f"Decks: {len(decks_out)} (davon archiviert: {sum(1 for d in decks_out if d['archived'])})")
    print(f"Partien: {len(games_out)}")
    print(f"Deck-Verleih-Faelle (jetzt korrekt verlinkt): {lending_cases_count} in {lending_games_count} Partien")
    if unresolved_lending_cases:
        print(f"WARNUNG - nicht aufloesbare Faelle (Deck in keiner Deck-Liste gefunden): {unresolved_lending_cases}")
    print(f"Geschrieben nach: {DST}")


if __name__ == "__main__":
    main()
