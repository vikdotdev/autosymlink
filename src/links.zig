pub const Link = struct {
    source: []const u8,
    destination: []const u8,
    force: bool = false,
};

pub const Links = struct {
    links: []const Link,
};
