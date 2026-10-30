extends Area2D

var life_time: int = 1

func setup(_cell: Vector2i, icon_id: String):
	var sprite = get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var tex = IconManager.get_icon_or_null(icon_id)
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2(1, 1) 
	else:
		var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.3, 0.3))
		sprite.texture = ImageTexture.create_from_image(img)
		
	var tw = create_tween().set_loops()
	tw.tween_property(sprite, "position:y", -2.0, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sprite, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
