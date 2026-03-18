with open("C:/eo3/EraOnline/scripts/server/game_server.gd", "r", encoding="utf-8") as f:
    content = f.read()

old_rn = "const RESOURCE_NODES: Dictionary = {\n}"
new_rn = open("C:/eo3/EraOnline/tools/resource_nodes_block.txt", "r", encoding="utf-8").read()
assert old_rn in content, "RESOURCE_NODES not found"
content = content.replace(old_rn, new_rn, 1)
print("RESOURCE_NODES populated")

with open("C:/eo3/EraOnline/scripts/server/game_server.gd", "w", encoding="utf-8") as f:
    f.write(content)
print("Done")
