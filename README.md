# Scrub

Common Industrial Protocol over EtherNet/IP

## Usage

The goal of this library is to allow the encapsulation of Common Industrial
Protocol (CIP) messages over EtherNet/IP, with little overhead. Its is
intended to operate as an originator for querying a target. The `Scrub` module
will contain a few helper functions for performing all the necessary steps
for scaffolding a connection and sending unconnected messages.

### Reading a tag

Reading from a tag can be summarized by calling `Scrub.read_tag/2`

```elixir
{:ok, nil} = Scrub.read_tag("20.0.0.70", "NULL")
```
