# fltprog.nvim

WIP: Progress api concept(s) for neovim.

## Requirements

- neovim >= v0.11.0

## Instalation

Use a plugin manager to add this plugin to your installation, or download to a path in
your runtime path.
There are no other dependencies.

## How to use

To use this plugin:
1. Create a progress display, and register it to the categories you want it to work with.
2. Create a progress source, and register it to provide events for a single category.
3. With the progress source, create progress event that will be displayed by the registered
   progress displays that listen to the source category.

### Included Categories

* WORK (`'work'`): used for background work (like when waiting to receive data from somewhere, or waiting on a long running process).
* LSP (`'lsp'`): used for standard LSP communication.
Events require `client_id` to be set, so display can fetch client data.
* BUFFER (`'buffer'`): used when the progress has direct relation with a specific buffer.
Events require `buffer` to be set for the buffer nr the event is about.

## How to use v2

Inspired in the neovim talk about a progress interface, there is a v2 table with
a different api.

### Differences with v1

- Display does not require separate registration.
- Creation of events do not need to create distinct source, just pass a string or a
  number (do not mix v1 usage with v2)

Create display


Create and use a progress event
```lua
local progress = require('fltprogr').v2

local event = progres.create_event('srcid', progress.categories.LSP, { 
    -- event data ... 
})

progress.event_start(event)
-- ...
progress.event_update(event, { progress = 0.5 })
-- ...
progress.event_end(event)

```

## Usage (v1)

This plugin creates a progress source out of LSP `workDoneProgress` messages.
If you want to opt out, create the following variable.

```lua
vim.g.fltprog_autoregister = false
```
```vim
set g:fltprog_autoregister=v:false
```

Or pass to setup the following configuration
```lua
require('fltprogr').setup({ autoregister = false })
```

### Create a progress display

```lua
local progress = require('fltprog')

-- The event table contains the same information for all callbacks
--   - source integer source id
--   - id integer event id
--   - category string source category
--   - title string
--   - message string|nil
--   - progress number|true the progress in range of 0.0 to 1.0 (1 -> 100%), or `true` if indeterminate
--   - [string] any additional information passed by the source to the event

-- Create the progress event display
local id = progress.create_display({
    on_start = function(event)
        -- handle the start of the event
        vim.notify(event.title .. ' stated')
    end,
    on_update = function(event)
        -- handles an event update
        vim.notify(event.title .. ' updated')
    end,
    on_end = function(event)
        -- should remove (at some point) the event from display
        vim.notify(event.title .. ' ended')
    end,
})

-- register it
progress.display_register(id, progres.categories.LSP)
-- or progress.display_register(id, { progress.categories.LSP, 'CUSTOM' })
```

### Create a progress source

```lua
local progress = require('fltprog')

-- this is your source id, keep it to send progress events
local source = progress.create_source('CUSTOM')

-- ...

local event = progres.source_create_event(source, true --[[autostart]], {
    title = "My Progress Event", -- required,
    progress = 0.1, -- optional, if nil api assumes indeterminate progress
    message = "aditional information", -- optional, display chooses to use it or not
    background_data = {}, -- category specific data
    cancel = function() end, -- optional, callback function to cancell progress event
})

-- if you want to start the event at a later moment, you pass `false` in source_create_event
-- progress.source_event_start(source, event)

-- ...

-- to send progress updates
progress.source_event_update(source, event, {
    -- all optional data can be updated here, title changes will be ignored
})

-- ..

-- to signal the end of the progress event
progress.source_event_end(source, event, {
    -- same data as before
})

-- after this, event cannot be used anymore
```
