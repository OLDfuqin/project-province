class_name GeneratedScenarioHelpers
extends RefCounted


static func province_by_id(bridge: Object, id: String) -> Dictionary:
    for province: Dictionary in bridge.get_province_summaries():
        if province.get("id", "") == id:
            return province
    return {}


static func owned_provinces(bridge: Object, country_id: String) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for province: Dictionary in bridge.get_province_summaries():
        if province.get("owner_id", "") == country_id:
            result.append(province)
    result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
        return String(first.get("id", "")) < String(second.get("id", ""))
    )
    return result


static func first_adjacent_pair(bridge: Object, country_id: String) -> Array[String]:
    var owned := owned_provinces(bridge, country_id)
    var owned_ids: Dictionary = {}
    for province: Dictionary in owned:
        owned_ids[String(province.get("id", ""))] = true
    for province: Dictionary in owned:
        var first_id := String(province.get("id", ""))
        var neighbors: Array = province.get("neighbors", []).duplicate()
        neighbors.sort()
        for neighbor: String in neighbors:
            if owned_ids.has(neighbor) and first_id < neighbor:
                return [first_id, neighbor]
    return []


static func neutral_neighbor(bridge: Object, country_id: String) -> Array[String]:
    for province: Dictionary in owned_provinces(bridge, country_id):
        var first_id := String(province.get("id", ""))
        var neighbors: Array = province.get("neighbors", []).duplicate()
        neighbors.sort()
        for neighbor: String in neighbors:
            var other := province_by_id(bridge, neighbor)
            if other.get("owner_id", "") == "neutral":
                return [first_id, neighbor]
    return []


static func capital_id(country_id: String) -> String:
    return "capital_%s" % country_id
