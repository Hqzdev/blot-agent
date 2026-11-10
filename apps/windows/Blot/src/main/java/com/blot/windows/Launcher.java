package com.blot.windows;

public final class Launcher {
    private Launcher() {}
    public static void main(String[] arguments) {
        javafx.application.Application.launch(BlotApplication.class, arguments);
    }
}
