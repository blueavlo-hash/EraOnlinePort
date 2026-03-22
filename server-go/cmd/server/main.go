// Era Online Game Server — Go standalone server.
//
// Usage:
//
//	./eraonline-server [--config path/to/server.yaml]
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/config"
	"github.com/blueavlo-hash/eraonline-server/internal/db"
	"github.com/blueavlo-hash/eraonline-server/internal/gamedata"
	"github.com/blueavlo-hash/eraonline-server/internal/server"
	"github.com/blueavlo-hash/eraonline-server/internal/world"
)

func main() {
	cfgPath := flag.String("config", "config/server.yaml", "Path to server config file")
	flag.Parse()

	// Load configuration.
	cfg, err := config.Load(*cfgPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}

	// Set up logging.
	log := buildLogger(cfg)
	log.Info("Era Online server starting",
		"game_addr", cfg.Server.GameAddr,
		"http_addr", cfg.Server.HTTPAddr,
	)

	// Open database.
	database, err := db.Open(cfg.Database.Path, cfg.Database.MaxOpenConns)
	if err != nil {
		log.Error("database open failed", "err", err)
		os.Exit(1)
	}
	defer database.Close()
	log.Info("database open", "path", cfg.Database.Path)

	// Load game data.
	gd, err := gamedata.Load(cfg.Game.GameDataDir)
	if err != nil {
		log.Error("game data load failed", "err", err)
		os.Exit(1)
	}
	log.Info("game data loaded", "maps", len(gd.Maps), "npcs", len(gd.NPCs), "objects", len(gd.Objects))

	// Create world.
	worldCfg := world.Config{
		TickRateMS:       cfg.Game.TickRateMS,
		CombatTickMS:     cfg.Game.CombatTickMS,
		SpawnMap:         cfg.Game.SpawnMap,
		SpawnX:           cfg.Game.SpawnX,
		SpawnY:           cfg.Game.SpawnY,
		NightBrightness:  cfg.Game.NightBrightness,
		DayLengthSeconds: cfg.Game.DayLengthSeconds,
		AutosaveInterval: 5 * time.Minute,
	}
	w := world.New(worldCfg, database, gd, log.With("component", "world"))

	// Create game server.
	srv, err := server.New(cfg, database, w, log.With("component", "server"))
	if err != nil {
		log.Error("server setup failed", "err", err)
		os.Exit(1)
	}

	// Create HTTP API (pass srv so it can issue launcher tokens).
	httpSrv := server.NewHTTPServer(cfg.Server.HTTPAddr, database, w, srv, log.With("component", "http"))

	// Root context.
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	// Start all services concurrently.
	errCh := make(chan error, 3)
	go func() { errCh <- w.Run(ctx); }()
	go func() { errCh <- srv.ListenAndServe(ctx) }()
	go func() { errCh <- httpSrv.ListenAndServe(ctx) }()

	// Wait for shutdown or error.
	select {
	case <-ctx.Done():
		log.Info("shutdown signal received")
	case err := <-errCh:
		if err != nil {
			log.Error("fatal error", "err", err)
			cancel()
		}
	}

	log.Info("shutting down — waiting for world to save...")
	// Give the world loop time to save all players.
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer shutdownCancel()

	// Drain remaining errors.
	done := make(chan struct{})
	go func() {
		for range [3]struct{}{} {
			<-errCh
		}
		close(done)
	}()

	select {
	case <-done:
	case <-shutdownCtx.Done():
		log.Warn("shutdown timed out")
	}

	log.Info("server stopped")
}

func buildLogger(cfg *config.Config) *slog.Logger {
	level := slog.LevelInfo
	switch cfg.Log.Level {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	}

	opts := &slog.HandlerOptions{Level: level}
	var handler slog.Handler

	out := os.Stderr
	if cfg.Log.File != "" {
		f, err := os.OpenFile(cfg.Log.File, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
		if err == nil {
			out = f
		}
	}

	if cfg.Log.Format == "json" {
		handler = slog.NewJSONHandler(out, opts)
	} else {
		handler = slog.NewTextHandler(out, opts)
	}

	return slog.New(handler)
}
