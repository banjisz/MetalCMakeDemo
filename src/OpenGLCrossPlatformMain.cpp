#include <GLFW/glfw3.h>

#include <cmath>
#include <iostream>

int main()
{
    if (!glfwInit())
    {
        std::cerr << "Failed to initialize GLFW" << std::endl;
        return 1;
    }

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);

    GLFWwindow *window = glfwCreateWindow(1280, 720, "OpenGL Cross-Platform Demo", nullptr, nullptr);
    if (!window)
    {
        std::cerr << "Failed to create GLFW window" << std::endl;
        glfwTerminate();
        return 1;
    }

    glfwMakeContextCurrent(window);
    glfwSwapInterval(1);

    const double startTime = glfwGetTime();
    while (!glfwWindowShouldClose(window))
    {
        int width = 0;
        int height = 0;
        glfwGetFramebufferSize(window, &width, &height);
        glViewport(0, 0, width, height);

        const float t = static_cast<float>(glfwGetTime() - startTime);
        const float r = 0.10f + 0.05f * std::sin(t * 0.60f);
        const float g = 0.12f + 0.05f * std::cos(t * 0.45f);
        const float b = 0.18f + 0.04f * std::sin(t * 0.33f + 1.2f);

        glClearColor(r, g, b, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glRotatef(t * 45.0f, 0.0f, 0.0f, 1.0f);

        glBegin(GL_TRIANGLES);
        glColor3f(1.0f, 0.35f, 0.20f);
        glVertex2f(0.0f, 0.70f);
        glColor3f(0.20f, 0.75f, 1.0f);
        glVertex2f(-0.75f, -0.55f);
        glColor3f(0.30f, 1.0f, 0.45f);
        glVertex2f(0.75f, -0.55f);
        glEnd();

        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    glfwDestroyWindow(window);
    glfwTerminate();
    return 0;
}
