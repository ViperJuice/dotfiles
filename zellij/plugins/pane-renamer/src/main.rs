use std::collections::BTreeMap;
use zellij_tile::prelude::*;

#[derive(Default)]
struct PaneRenamer;

register_plugin!(PaneRenamer);

impl ZellijPlugin for PaneRenamer {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[PermissionType::ChangeApplicationState]);
        subscribe(&[EventType::PermissionRequestResult]);
    }

    fn pipe(&mut self, pipe_message: PipeMessage) -> bool {
        // Debug: always try to rename regardless of message name
        if let Some(payload) = &pipe_message.payload {
            if let Some((id_str, title)) = payload.split_once(':') {
                if let Ok(pane_id) = id_str.parse::<u32>() {
                    rename_terminal_pane(pane_id, title);
                }
            }
        }
        false // Don't block the pipe
    }

    fn update(&mut self, _event: Event) -> bool {
        false // No rendering needed
    }

    fn render(&mut self, _rows: usize, _cols: usize) {
        // This plugin has no UI
    }
}
