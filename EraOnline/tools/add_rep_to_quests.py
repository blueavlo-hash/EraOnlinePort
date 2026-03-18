with open('C:/eo3/EraOnline/scripts/server/server_quests.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Each quest's completion_msg is unique — add rep_faction before it
quest_rep_map = [
    # (unique completion_msg snippet, faction, amount)
    ("Well done, warrior. You are ready for greater challenges.",         "haven",      75),
    ("Excellent! These materials will serve you well.",                   "haven",      75),
    ("Thank you for the message. The Elder was right to send you.",       "haven",      50),
    ("The roads are safer now. Thank you, adventurer.",                   "haven",     100),
    ("The ancient threat is no more. The village owes you a great debt.", "haven",     150),
    ("Good haul! Now let me show you what to do with all this ore.",      "ironhaven", 100),
    ("Fine steel! Now you are ready to forge real weapons.",              "ironhaven", 150),
    ("An excellent piece of work! You have the makings of a true smith.", "ironhaven", 175),
    ("The militia is armed and ready. You have done great service for this town.", "ironhaven", 200),
    ("Delicious! You have real talent in the kitchen.",                   "thornwall", 100),
    ("The village will eat well this winter, thanks to you!",             "thornwall", 150),
    ("What a wonderful catch! The feast will be remembered for years.",   "thornwall", 125),
    ("Well done! The roads are safe again for now.",                      "thornwall", 100),
    ("Good scouting! Now we know what lurks out there.",                  "thornwall",  75),
    ("Those trolls won",                                                  "thornwall", 175),
    ("Those ruins are indeed dangerous. Good to have a full report.",     "thornwall", 100),
    ("Perfect! That",                                                     "haven",      75),
    ("Good clean cuts! Those planks will build something fine.",          "haven",     100),
    ("Excellent stock! The trade caravans will be pleased.",              "haven",     125),
    ("Impressive! You have proven yourself worthy of learning the higher arts.", "sealport", 150),
]

count = 0
for (msg_snippet, faction, amount) in quest_rep_map:
    marker = '"completion_msg":  "' + msg_snippet
    if marker not in content:
        print(f"MISS: {msg_snippet[:50]!r}")
        continue
    rep_line = f'"rep_faction": "{faction}", "rep_amount": {amount},\n\t\t'
    content = content.replace(marker, rep_line + marker, 1)
    count += 1

print(f"Applied {count} rep faction annotations")
with open('C:/eo3/EraOnline/scripts/server/server_quests.gd', 'w', encoding='utf-8') as f:
    f.write(content)
print("Done.")
