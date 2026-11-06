extends GutTest

const EDITOR_SCENE: PackedScene = preload("res://src/meme/editor/meme_editor.tscn")

var _editor: MemeEditor


func before_each() -> void:
	_editor = EDITOR_SCENE.instantiate()
	add_child_autofree(_editor)


func test_starts_with_the_first_template_and_no_captions() -> void:
	var draft: MemeSpec = _editor.get_draft()
	assert_eq(draft.template_id, MemeTemplateLibrary.get_default().ids()[0])
	assert_eq(draft.top_text, "")
	assert_false(_editor.has_submitted())


func test_draft_follows_template_and_captions() -> void:
	var library: MemeTemplateLibrary = MemeTemplateLibrary.get_default()
	_editor.select_template(library.ids()[2])
	_editor.set_captions("  top\ttext ", "bottom")
	var draft: MemeSpec = _editor.get_draft()
	assert_eq(draft.template_id, library.ids()[2])
	assert_eq(draft.top_text, "top text", "captions are sanitized like on the server")
	assert_eq(draft.bottom_text, "bottom")


func test_submit_emits_the_draft() -> void:
	watch_signals(_editor)
	_editor.set_captions("ME", "ALSO ME")
	_editor.submit()
	assert_signal_emitted(_editor, "submitted")
	var spec: MemeSpec = get_signal_parameters(_editor, "submitted")[0]
	assert_eq(spec.bottom_text, "ALSO ME")
	assert_true(_editor.has_submitted())


func test_resubmitting_is_allowed() -> void:
	watch_signals(_editor)
	_editor.submit()
	_editor.set_captions("better", "")
	_editor.submit()
	assert_signal_emit_count(_editor, "submitted", 2)


func test_time_running_out_submits_the_draft_once() -> void:
	watch_signals(_editor)
	_editor.set_captions("last", "second")
	_editor.set_time_left(0.05)
	_editor._process(0.1)
	_editor._process(0.1)
	assert_signal_emit_count(_editor, "submitted", 1)
	assert_signal_emit_count(_editor, "time_ran_out", 1)


func test_time_running_out_does_not_resend_an_unchanged_meme() -> void:
	watch_signals(_editor)
	_editor.submit()
	_editor.set_time_left(0.05)
	_editor._process(0.1)
	assert_signal_emit_count(_editor, "submitted", 1)
