## 只缓存不可变来源收据的 JSON 字节；每次保存仍读取最新来源、保底和首奖状态。
## 缓存最多持有当前账本的一份条目编码、一份合并编码及引用，不累积历史版本。
## 保留排序与完整载荷，未领取首奖、已领取物品和防重证据不压缩、不删除。
extends RefCounted

var _source: Dictionary = {}
var _entries: Dictionary = {}
var _ordered_keys: Array = []
var _insertion_keys: Array = []
var _body := PackedByteArray()
var _insertion_values: Array = []
var _all_immutable := false
var encoded_receipts := 0

func encode(state: Dictionary) -> PackedByteArray:
	var metadata := state.duplicate()
	var receipts: Dictionary = metadata.get("receipts", {})
	metadata.erase("receipts")
	var payload := JSON.stringify(metadata, "", true).to_utf8_buffer()
	payload.resize(payload.size() - 1)
	# 外部或最小账本可能只有 receipts；空对象首成员前不能加逗号。
	if not metadata.is_empty(): payload.append(44)
	payload.append_array('"receipts":{'.to_utf8_buffer())
	if not is_same(receipts, _source):
		clear()
		_source = receipts
	var keys := receipts.keys()
	var changed := keys != _insertion_keys
	# 热路径只比较键序及对象身份；已证明深只读的对象无需再读其内部元数据。
	if not changed and _all_immutable:
		var values := receipts.values()
		var identical := true
		for index in values.size():
			if not is_same(values[index], _insertion_values[index]):
				identical = false
				break
		if identical:
			payload.append_array(_body)
			payload.append_array('}}'.to_utf8_buffer())
			return payload
	if changed:
		_insertion_keys = keys
		_ordered_keys = keys.duplicate()
		_ordered_keys.sort()
		for key: Variant in _entries.keys():
			if not receipts.has(key):
				_entries.erase(key)
	# 公共字典允许同数量替换/删除，不以 size 或调用次数推断没有改变。
	for key: Variant in _ordered_keys:
		var receipt: Variant = receipts[key]
		var cached: Dictionary = _entries.get(key, {})
		# GearDrops 生成/消毒的收据递归只读；手工或可变收据每次完整编码。
		if not cached.is_empty() and cached["immutable"] and is_same(cached["receipt"], receipt):
			continue
		_entries[key] = {"receipt": receipt, "immutable": _deep_read_only(receipt),
			"json": JSON.stringify(str(key)) + ":" + JSON.stringify(receipt, "", true)}
		encoded_receipts += 1
		changed = true
	_insertion_values = receipts.values()
	_all_immutable = true
	for key: Variant in _ordered_keys:
		_all_immutable = _all_immutable and bool(_entries[key]["immutable"])
	if changed:
		# 一次 join 分配代替逐收据 append 导致的反复扩容；新击杀只重新编码新收据。
		var members := PackedStringArray()
		for key: Variant in _ordered_keys:
			members.append(_entries[key]["json"])
		_body = ",".join(members).to_utf8_buffer()
	payload.append_array(_body)
	payload.append_array('}}'.to_utf8_buffer())
	return payload

func clear() -> void:
	_source = {}
	_entries.clear()
	_ordered_keys.clear()
	_insertion_keys.clear()
	_insertion_values.clear()
	_all_immutable = false
	_body = PackedByteArray()

## 顶层只读不代表嵌套数组只读。仅在新对象首次编码时验证；深只读一经成立不可撤销。
func _deep_read_only(value: Variant) -> bool:
	if value is Dictionary:
		if not value.is_read_only(): return false
		for child: Variant in value.values():
			if not _deep_read_only(child): return false
	elif value is Array:
		if not value.is_read_only(): return false
		for child: Variant in value:
			if not _deep_read_only(child): return false
	elif typeof(value) not in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]:
		return false
	return true
