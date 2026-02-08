# Model Configuration

## Default Model Selection

By default, `settings.json` does **not** specify a model override. This allows Claude Code to use its built-in default model selection logic, which typically chooses the most appropriate model based on context and capabilities.

## Overriding Model Per Session

You can override the model for a specific session using CLI flags:

```bash
# Use Opus 4.6 (most capable, highest cost)
claude --model opus

# Use Sonnet 4.5 (balanced capability and cost)
claude --model sonnet

# Use Haiku 4.5 (fastest, lowest cost)
claude --model haiku
```

## Setting a Persistent Default

If you want to always use a specific model, add to `settings.json`:

```json
{
  "model": "opus",
  "hooks": { ... },
  "statusLine": { ... }
}
```

Valid values: `"opus"`, `"sonnet"`, `"haiku"`

**Note**: Setting a persistent default in `settings.json` overrides Claude Code's intelligent model selection. Only do this if you have a specific preference.

## Statusline Display

The custom statusline (`statusline-custom.sh`) displays the current model in abbreviated format:

- **H4.5** - Haiku 4.5
- **S4.5** - Sonnet 4.5
- **O4.6** - Opus 4.6

This format is compact and clearly identifies both the model family and version.

### Model Display Parsing

The statusline extracts model information from various formats:
- "Sun at 4.5" → "S4.5"
- "claude-sonnet-4-5" → "S4.5"
- "Haiku 4.5" → "H4.5"
- "Opus 4.6" → "O4.6"

## Cost Implications

Different models have different costs per token:

| Model | Capability | Speed | Relative Cost |
|-------|-----------|-------|---------------|
| Haiku 4.5 | Good | Fastest | Lowest (1x) |
| Sonnet 4.5 | Excellent | Fast | Medium (3x) |
| Opus 4.6 | Best | Slower | Highest (15x) |

The statusline shows total cost in USD for the current conversation: `💰 $0.15`

## Checking Current Model

The statusline always shows the active model. If you need to verify which model is in use:

1. Look at the statusline display (e.g., "S4.5")
2. Or ask Claude: "What model are you?"
3. Or check the transcript JSON (includes full model metadata)

## Recommended Workflow

For most development work:
- **Default (no override)**: Let Claude Code choose intelligently
- **Quick tasks**: `claude --model haiku` for speed and cost savings
- **Complex tasks**: `claude --model opus` for maximum capability
- **Balanced**: `claude --model sonnet` (default for most sessions)
