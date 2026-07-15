-- Only immutable, non-sensitive engine configuration is readable outside the
-- owner. Dynamic state and base map/asset tables deliberately receive no grant;
-- later phases expose them solely through the definer-rights DOOM_API package.
grant select on doom_config to public;
