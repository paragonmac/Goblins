// Player interaction modes for Goblinoria

pub const PlayerMode = enum {
    /// Click to inspect blocks/workers - no selection rectangle
    information,
    /// Select blocks to queue dig tasks for workers
    dig,
    /// Select empty spaces to queue place tasks for workers
    place,
    /// Select solid blocks to convert to stairs
    stairs,

    pub fn displayName(self: PlayerMode) [:0]const u8 {
        return switch (self) {
            .information => "Info",
            .dig => "Dig",
            .place => "Place",
            .stairs => "Stairs",
        };
    }

    pub fn keyHint(self: PlayerMode) [:0]const u8 {
        return switch (self) {
            .information => "[1]",
            .dig => "[2]",
            .place => "[3]",
            .stairs => "[4]",
        };
    }
};
