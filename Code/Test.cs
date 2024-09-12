using Godot;
using System;

public partial class Test : Sprite2D
{
	private int _speed = 400;
	private float _angularSpeed = Mathf.Pi;
	public Test()
	{
		GD.Print("Hello from Test!");
	}
	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
		
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
		 Rotation += _angularSpeed * (float)delta;
        var velocity = Vector2.Up.Rotated(Rotation) * _speed;
        Position += velocity * (float)delta;
	}

	public void _on_toggle_button_pressed()
	{
		SetProcess(!IsProcessing());
	}
}
