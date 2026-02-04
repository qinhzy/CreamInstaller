using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using CreamInstaller.Components;

namespace CreamInstaller.Forms;

internal sealed partial class MarioForm : CustomForm
{
    private readonly GameInput input = new();
    private readonly Timer gameTimer;
    private MarioWorld world;

    internal MarioForm(IWin32Window owner) : base(owner)
    {
        InitializeComponent();
        world = new MarioWorld(ClientSize);
        gameTimer = new Timer { Interval = 16, Enabled = true };
        gameTimer.Tick += (_, _) => TickGame();
        Shown += (_, _) => Focus();
    }

    private void TickGame()
    {
        world.Update(input, ClientSize);
        input.EndFrame();
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        world.Draw(e.Graphics, ClientSize);
    }

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        input.SetKey(e.KeyCode, true);
        if (e.KeyCode is Keys.Escape)
            Close();
    }

    private void OnKeyUp(object sender, KeyEventArgs e) => input.SetKey(e.KeyCode, false);

    private void OnResizeGame(object sender, EventArgs e) => world?.Resize(ClientSize);

    private sealed class GameInput
    {
        internal bool LeftHeld;
        internal bool RightHeld;
        internal bool JumpHeld;
        internal bool JumpPressed;
        internal bool RestartPressed;

        internal void SetKey(Keys key, bool isDown)
        {
            switch (key)
            {
                case Keys.A:
                case Keys.Left:
                    LeftHeld = isDown;
                    break;
                case Keys.D:
                case Keys.Right:
                    RightHeld = isDown;
                    break;
                case Keys.W:
                case Keys.Up:
                case Keys.Space:
                    if (isDown && !JumpHeld)
                        JumpPressed = true;
                    JumpHeld = isDown;
                    break;
                case Keys.R:
                    if (isDown)
                        RestartPressed = true;
                    break;
            }
        }

        internal void EndFrame()
        {
            JumpPressed = false;
            RestartPressed = false;
        }
    }

    private sealed class MarioWorld
    {
        private const float Gravity = 0.65f;
        private const float MoveAcceleration = 0.25f;
        private const float MoveSpeed = 4f;
        private const float JumpStrength = 11f;
        private const float MaxFallSpeed = 14f;
        private const int JumpBufferFrames = 8;
        private const int CoyoteFrames = 8;

        private readonly List<RectangleF> platforms = new();
        private readonly List<MarioEnemy> enemies = new();
        private readonly List<MarioCoin> coins = new();
        private readonly PointF spawnPoint = new(32f, 280f);
        private readonly float levelWidth = 1900f;
        private readonly float levelHeight = 420f;

        private RectangleF goalPole;
        private Player player;
        private float cameraX;
        private int jumpBufferTimer;
        private int coyoteTimer;
        private int lives = 3;
        private int score;
        private int collectedCoins;
        private bool victory;
        private bool gameOver;

        internal MarioWorld(Size viewport)
        {
            ResetLevel();
            UpdateCamera(viewport);
        }

        internal void Resize(Size viewport) => UpdateCamera(viewport);

        internal void Update(GameInput input, Size viewport)
        {
            if (input.RestartPressed)
            {
                ResetWorld(viewport);
                return;
            }
            if (victory || gameOver)
                return;
            ApplyInput(input);
            ApplyPhysics();
            CollectCoins();
            UpdateEnemies(viewport);
            CheckGoal();
            CheckFalls(viewport);
            UpdateCamera(viewport);
        }

        internal void Draw(Graphics graphics, Size viewport)
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.Clear(Color.FromArgb(142, 205, 255));
            using SolidBrush skyBrush = new(Color.FromArgb(100, 198, 255));
            graphics.FillRectangle(skyBrush, 0, 0, viewport.Width, viewport.Height);
            graphics.TranslateTransform(-cameraX, 0);
            DrawBackdrop(graphics);
            using SolidBrush platformBrush = new(Color.SaddleBrown);
            foreach (RectangleF platform in platforms)
                graphics.FillRectangle(platformBrush, platform);
            DrawCoins(graphics);
            DrawEnemies(graphics);
            DrawFlag(graphics);
            DrawPlayer(graphics);
            graphics.ResetTransform();
            DrawOverlay(graphics, viewport);
        }

        private void ResetWorld(Size viewport)
        {
            lives = 3;
            score = 0;
            collectedCoins = 0;
            victory = false;
            gameOver = false;
            ResetLevel();
            UpdateCamera(viewport);
        }

        private void ResetLevel()
        {
            platforms.Clear();
            coins.Clear();
            enemies.Clear();
            BuildPlatforms();
            BuildCoins();
            BuildEnemies();
            player = new Player(spawnPoint);
            jumpBufferTimer = 0;
            coyoteTimer = 0;
        }

        private void BuildPlatforms()
        {
            platforms.Add(new RectangleF(0f, 340f, levelWidth, 80f)); // ground
            platforms.Add(new RectangleF(180f, 300f, 160f, 20f));
            platforms.Add(new RectangleF(430f, 260f, 120f, 20f));
            platforms.Add(new RectangleF(640f, 220f, 180f, 20f));
            platforms.Add(new RectangleF(940f, 280f, 140f, 20f));
            platforms.Add(new RectangleF(1180f, 240f, 160f, 20f));
            platforms.Add(new RectangleF(1460f, 200f, 140f, 20f));
            platforms.Add(new RectangleF(1660f, 280f, 120f, 20f));
            goalPole = new RectangleF(levelWidth - 80f, 180f, 14f, 240f);
        }

        private void BuildCoins()
        {
            for (int i = 0; i < 5; i++)
                coins.Add(new MarioCoin(new RectangleF(210f + i * 30f, 260f, 20f, 20f)));
            coins.Add(new MarioCoin(new RectangleF(470f, 220f, 20f, 20f)));
            coins.Add(new MarioCoin(new RectangleF(520f, 220f, 20f, 20f)));
            coins.Add(new MarioCoin(new RectangleF(680f, 180f, 20f, 20f)));
            coins.Add(new MarioCoin(new RectangleF(710f, 180f, 20f, 20f)));
            coins.Add(new MarioCoin(new RectangleF(740f, 180f, 20f, 20f)));
            coins.Add(new MarioCoin(new RectangleF(980f, 240f, 20f, 20f)));
            coins.Add(new MarioCoin(new RectangleF(1020f, 240f, 20f, 20f)));
            coins.Add(new MarioCoin(new RectangleF(1220f, 200f, 20f, 20f)));
            coins.Add(new MarioCoin(new RectangleF(1250f, 200f, 20f, 20f)));
            coins.Add(new MarioCoin(new RectangleF(1500f, 160f, 20f, 20f)));
            coins.Add(new MarioCoin(new RectangleF(1530f, 160f, 20f, 20f)));
        }

        private void BuildEnemies()
        {
            enemies.Add(new MarioEnemy(new RectangleF(320f, 312f, 36f, 28f), 1.6f, 260f, 420f));
            enemies.Add(new MarioEnemy(new RectangleF(860f, 312f, 36f, 28f), -1.4f, 780f, 940f));
            enemies.Add(new MarioEnemy(new RectangleF(1320f, 312f, 36f, 28f), 1.8f, 1260f, 1440f));
        }

        private void ApplyInput(GameInput input)
        {
            float targetSpeed = 0f;
            if (input.LeftHeld)
                targetSpeed -= MoveSpeed;
            if (input.RightHeld)
                targetSpeed += MoveSpeed;
            float xVelocity = player.Velocity.X + (targetSpeed - player.Velocity.X) * MoveAcceleration;
            player.Velocity = new PointF(xVelocity, player.Velocity.Y + Gravity);
            player.Velocity = new PointF(Math.Clamp(player.Velocity.X, -MoveSpeed, MoveSpeed),
                Math.Min(player.Velocity.Y, MaxFallSpeed));
            if (input.JumpPressed)
                jumpBufferTimer = JumpBufferFrames;
            if (jumpBufferTimer > 0)
                jumpBufferTimer--;
            if (player.OnGround)
                coyoteTimer = CoyoteFrames;
            else if (coyoteTimer > 0)
                coyoteTimer--;
            if ((player.OnGround || coyoteTimer > 0) && jumpBufferTimer > 0)
            {
                player.Velocity = new PointF(player.Velocity.X, -JumpStrength);
                player.OnGround = false;
                jumpBufferTimer = 0;
            }
        }

        private void ApplyPhysics()
        {
            RectangleF horizontal = player.Bounds;
            horizontal.X += player.Velocity.X;
            foreach (RectangleF platform in platforms)
            {
                if (!horizontal.IntersectsWith(platform))
                    continue;
                if (player.Velocity.X > 0)
                    horizontal.X = platform.Left - horizontal.Width;
                else if (player.Velocity.X < 0)
                    horizontal.X = platform.Right;
                player.Velocity = new PointF(0f, player.Velocity.Y);
            }
            player.Bounds = horizontal;
            RectangleF vertical = player.Bounds;
            vertical.Y += player.Velocity.Y;
            player.OnGround = false;
            foreach (RectangleF platform in platforms)
            {
                if (!vertical.IntersectsWith(platform))
                    continue;
                if (player.Velocity.Y > 0)
                {
                    vertical.Y = platform.Top - vertical.Height;
                    player.OnGround = true;
                    coyoteTimer = CoyoteFrames;
                }
                else if (player.Velocity.Y < 0)
                    vertical.Y = platform.Bottom;
                player.Velocity = new PointF(player.Velocity.X, 0f);
            }
            player.Bounds = vertical;
        }

        private void UpdateEnemies(Size viewport)
        {
            foreach (MarioEnemy enemy in enemies)
            {
                if (!enemy.Alive)
                    continue;
                enemy.Advance(platforms);
                if (!enemy.Bounds.IntersectsWith(player.Bounds))
                    continue;
                bool stomped = player.Velocity.Y > 0 && player.Bounds.Bottom <= enemy.Bounds.Top + 12f;
                if (stomped)
                {
                    enemy.Alive = false;
                    player.Velocity = new PointF(player.Velocity.X, -JumpStrength * 0.6f);
                    score += 200;
                }
                else
                {
                    LoseLife(viewport);
                    return;
                }
            }
        }

        private void CollectCoins()
        {
            for (int i = 0; i < coins.Count; i++)
            {
                MarioCoin coin = coins[i];
                if (coin.Collected || !coin.Bounds.IntersectsWith(player.Bounds))
                    continue;
                coin.Collected = true;
                coins[i] = coin;
                collectedCoins++;
                score += 50;
            }
        }

        private void CheckGoal()
        {
            if (!player.Bounds.IntersectsWith(goalPole))
                return;
            victory = true;
            score += 500 + collectedCoins * 10;
        }

        private void CheckFalls(Size viewport)
        {
            if (player.Bounds.Bottom < levelHeight + 200f)
                return;
            LoseLife(viewport);
        }

        private void LoseLife(Size viewport)
        {
            lives--;
            if (lives < 0)
            {
                gameOver = true;
                return;
            }
            player = new Player(spawnPoint);
            jumpBufferTimer = 0;
            coyoteTimer = 0;
            UpdateCamera(viewport);
        }

        private void UpdateCamera(Size viewport)
        {
            cameraX = Math.Clamp(player.Bounds.X + player.Bounds.Width / 2f - viewport.Width / 2f, 0f,
                Math.Max(levelWidth - viewport.Width, 0f));
        }

        private void DrawBackdrop(Graphics graphics)
        {
            using SolidBrush hillBrush = new(Color.FromArgb(120, 200, 120));
            graphics.FillEllipse(hillBrush, 150f, 280f, 260f, 140f);
            graphics.FillEllipse(hillBrush, 520f, 260f, 300f, 160f);
            graphics.FillEllipse(hillBrush, 1040f, 270f, 320f, 150f);
            graphics.FillEllipse(hillBrush, 1480f, 280f, 260f, 140f);
        }

        private void DrawCoins(Graphics graphics)
        {
            using Pen coinOutline = new(Color.Goldenrod, 2f);
            using SolidBrush coinBrush = new(Color.Gold);
            foreach (MarioCoin coin in coins)
            {
                if (coin.Collected)
                    continue;
                graphics.FillEllipse(coinBrush, coin.Bounds);
                graphics.DrawEllipse(coinOutline, coin.Bounds);
            }
        }

        private void DrawEnemies(Graphics graphics)
        {
            using SolidBrush enemyBrush = new(Color.FromArgb(192, 96, 64));
            using Pen eyePen = new(Color.White, 2f);
            foreach (MarioEnemy enemy in enemies)
            {
                if (!enemy.Alive)
                    continue;
                graphics.FillRectangle(enemyBrush, enemy.Bounds);
                RectangleF eyeLeft = new(enemy.Bounds.X + 8f, enemy.Bounds.Y + 6f, 6f, 6f);
                RectangleF eyeRight = new(enemy.Bounds.X + enemy.Bounds.Width - 14f, enemy.Bounds.Y + 6f, 6f, 6f);
                graphics.DrawEllipse(eyePen, eyeLeft);
                graphics.DrawEllipse(eyePen, eyeRight);
            }
        }

        private void DrawPlayer(Graphics graphics)
        {
            RectangleF body = player.Bounds;
            using SolidBrush suitBrush = new(Color.Firebrick);
            using SolidBrush faceBrush = new(Color.Bisque);
            using SolidBrush hatBrush = new(Color.Maroon);
            graphics.FillRectangle(suitBrush, body);
            RectangleF face = new(body.X + 6f, body.Y + 6f, body.Width - 12f, body.Height / 2.5f);
            graphics.FillRectangle(faceBrush, face);
            RectangleF hat = new(body.X + 2f, body.Y - 4f, body.Width - 4f, 10f);
            graphics.FillRectangle(hatBrush, hat);
        }

        private void DrawFlag(Graphics graphics)
        {
            using SolidBrush poleBrush = new(Color.White);
            using SolidBrush flagBrush = new(Color.ForestGreen);
            graphics.FillRectangle(poleBrush, goalPole);
            RectangleF banner = new(goalPole.Right, goalPole.Top + 24f, 42f, 24f);
            graphics.FillPolygon(flagBrush, new[]
            {
                new PointF(banner.Left, banner.Top),
                new PointF(banner.Right, banner.Top + banner.Height / 2f),
                new PointF(banner.Left, banner.Bottom)
            });
        }

        private void DrawOverlay(Graphics graphics, Size viewport)
        {
            const string instructionText = "A / D or Arrow Keys: Move    Space / W / Up: Jump    R: Restart    ESC: Close";
            string state = victory ? "You reached the flag! Press R to play again."
                : gameOver ? "Game over! Press R to try again."
                : "Reach the flag while avoiding enemies.";
            using StringFormat format = new() { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center };
            TextRenderer.DrawText(graphics, $"Coins: {collectedCoins}    Score: {score}    Lives: {Math.Max(lives, 0)}",
                SystemFonts.CaptionFont, new Point(10, 10), Color.Black);
            TextRenderer.DrawText(graphics, state, SystemFonts.CaptionFont, new Point(10, 32), Color.DarkRed);
            TextRenderer.DrawText(graphics, instructionText, SystemFonts.DefaultFont,
                new Rectangle(0, viewport.Height - 26, viewport.Width, 24), Color.Black,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }

        private struct Player
        {
            internal RectangleF Bounds;
            internal PointF Velocity;
            internal bool OnGround;

            internal Player(PointF spawnPoint)
            {
                Bounds = new RectangleF(spawnPoint, new SizeF(32f, 36f));
                Velocity = PointF.Empty;
                OnGround = false;
            }
        }

        private sealed class MarioEnemy
        {
            internal RectangleF Bounds;
            internal bool Alive = true;
            private float Speed;
            private readonly float leftLimit;
            private readonly float rightLimit;

            internal MarioEnemy(RectangleF bounds, float speed, float leftLimit, float rightLimit)
            {
                Bounds = bounds;
                Speed = speed;
                this.leftLimit = leftLimit;
                this.rightLimit = rightLimit;
            }

            internal void Advance(List<RectangleF> platforms)
            {
                RectangleF next = Bounds;
                next.X += Speed;
                foreach (RectangleF platform in platforms)
                {
                    if (!next.IntersectsWith(platform))
                        continue;
                    Speed = -Speed;
                    return;
                }
                if (next.Left <= leftLimit || next.Right >= rightLimit)
                    Speed = -Speed;
                else
                    Bounds = next;
            }
        }

        private struct MarioCoin
        {
            internal RectangleF Bounds;
            internal bool Collected;

            internal MarioCoin(RectangleF bounds)
            {
                Bounds = bounds;
                Collected = false;
            }
        }
    }
}
