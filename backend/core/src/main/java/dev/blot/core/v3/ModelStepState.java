package dev.blot.core.v3;

public enum ModelStepState {
  PREPARED,
  RUNNING,
  WAITING_TOOLS,
  COMPLETED,
  INTERRUPTED,
  CANCELED,
  FAILED
}
