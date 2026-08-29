"""Programmatic control of the Connect IQ simulator.

The simulator has no plugin API, so everything here drives it from outside: the
persisted-settings file on disk, macOS window capture, and the SDK's own command line.
Each module is usable on its own from the shell, which is what keeps them testable
independently of the MCP server layered over them.
"""
