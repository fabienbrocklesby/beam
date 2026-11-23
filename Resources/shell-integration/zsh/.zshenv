# Beam's zsh integration. Beam starts a pane's zsh with ZDOTDIR set to this
# directory, so zsh reads this file before any of the user's own.
#
# The user's aliases may already be on, so every command word is quoted to
# keep them out.

# Ghostty's integration goes first: it puts ZDOTDIR back, reads the user's own
# .zshenv and loads itself.
'builtin' 'source' '--' "$BEAM_GHOSTTY_ZDOTDIR/.zshenv"
'builtin' 'unset' 'BEAM_GHOSTTY_ZDOTDIR'

# An agent typed by hand starts with the hooks Beam gives the ones it types
# itself (AgentHooks in BeamCore), so its pane shows its state too. Defined
# before the user's own files run, so a function of theirs with the same name
# replaces these, and with `function`, which keeps an alias of the same name
# from being expanded here.
if [[ -o 'interactive' ]]; then
    function claude {
        'builtin' 'emulate' '-L' 'zsh'
        # Claude Code reads only the last --settings, so one that is already
        # there stands: the user's own, or the one Beam typed.
        if [[ -n ${BEAM_CLAUDE_SETTINGS-} && ${@[(I)--settings(|=*)]} -eq 0 ]]; then
            'builtin' 'command' claude --settings "$BEAM_CLAUDE_SETTINGS" "$@"
        else
            'builtin' 'command' claude "$@"
        fi
    }

    function codex {
        'builtin' 'emulate' '-L' 'zsh'
        if [[ -n ${BEAM_CODEX_HOOKS-} && ${@[(Ie)$BEAM_CODEX_HOOKS]} -eq 0 ]]; then
            'builtin' 'command' codex -c "$BEAM_CODEX_HOOKS" "$@"
        else
            'builtin' 'command' codex "$@"
        fi
    }
fi
