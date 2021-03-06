# Scrub

Common Industrial Protocol over EtherNet/IP

## Usage

The goal of this library is to allow the encapsulation of Common Industrial
Protocol (CIP) messages over EtherNet/IP, with little overhead. Its is
intended to operate as an originator for querying a target. The `Scrub` module
will contain a few helper functions for performing all the necessary steps
for scaffolding a connection and sending unconnected messages.

### Reading a tag

Reading from a tag can be summarized by:

1. Establishing/openning a session with the PLC
1. Requesting a tag from the PLC

```elixir
iex> {:ok, session} = Scrub.open_session("20.0.0.70")
iex> {:ok, value} = Scrub.read_tag(session,"All_EStops_OK_to_Run")
```

Reading Structure member -  Struct.Member_name[3]
```elixir
iex> {:ok, session} = Scrub.open_session("20.0.0.70")
iex> {:ok, value} = Scrub.read_tag(session,["Struct", "Member_name", 3])
```

Reading Bulk Tags -  "All_Estops_OK_to_Run" and Struct.Member_name[3]
```elixir
iex> {:ok, session} = Scrub.open_session("20.0.0.70")
iex> {:ok, value} = Scrub.bulk_read_tags(session,["All_Estops_OK_to_Run", ["Struct", "Member_name", 3]])
```

### Running Tests

```bash
$ mix test
```
