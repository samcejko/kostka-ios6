/*
 * Copyright (c) 2026 samcejko (Kostka: the iOS backend of LWJGL)
 * All rights reserved. BSD license, as LWJGL (see lwjgl/README.md).
 */

// GLSL 1.20 lets a uniform have an initial value ("uniform vec3 Gray = vec3(0.3, 0.59, 0.11);"); OpenGL ES 2.0 does
// not, and gl4es passes it on, so such a shader does not compile. Minecraft's post-processing shaders use it (the
// views of the mobs a spectator enters, Super Secret Settings, the April 2015 snapshot, which stops when its shader
// does not compile). Here the initial values are taken out of the source given to glShaderSource and set with
// glUniform once the program is linked. All of it runs on the game's thread, the one with the OpenGL context.
//
// And a fragment shader's loop that runs as many times as a uniform says - Minecraft's blur reads 41 texels a pixel
// at the radius of 20 its Super Secret Settings give it, blobs2 loops over a square, 256 of them - is more than the
// iPad 2's graphics can do for a whole screen: such a frame takes seconds, and a Minecraft frame of more than a
// second stops the game's clock (the game stands still for good, clicks and keys included). Such a uniform is used
// as min(uniform, cap): 8 for one loop over it, 3 for loops in loops. The effect keeps its kind, with a smaller
// radius. (KOSTKA_LOOP_CAPS=one,nested sets the caps for a test; 0 leaves the loops as they are.)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "ios_common.h"

typedef unsigned int ko_uint;
typedef void (*ko_shader_source_t)(ko_uint shader, int count, const char *const *strings, const int *lengths);
typedef void (*ko_attach_t)(ko_uint program, ko_uint shader);
typedef void (*ko_one_t)(ko_uint object);
typedef int (*ko_location_t)(ko_uint program, const char *name);
typedef void (*ko_uniformfv_t)(int location, int count, const float *value);
typedef void (*ko_uniformiv_t)(int location, int count, const int *value);
typedef void (*ko_getiv_t)(unsigned int pname, int *params);

#define KO_GL_CURRENT_PROGRAM 0x8B8D
#define KO_MAX_INITS 24
#define KO_MAX_SHADERS 64
#define KO_MAX_PROGRAMS 64

typedef struct {
    char name[64];
    int components;   // 1..4
    int isInt;
    float v[4];
} ko_init;

typedef struct {
    ko_uint shader;
    int count;
    ko_init inits[KO_MAX_INITS];
} ko_shader_inits;

typedef struct {
    ko_uint program;
    int count;
    ko_uint shaders[8];
} ko_program_shaders;

static ko_shader_inits g_shaders[KO_MAX_SHADERS];
static ko_program_shaders g_programs[KO_MAX_PROGRAMS];
static ko_shader_source_t g_shader_source;
static ko_attach_t g_attach;
static ko_one_t g_link, g_delete_shader, g_delete_program;

static void *ko_gl(const char *name)
{
    return ko_gl4es_proc_address(name);
}

static int ko_components(const char *type, int *isInt)
{
    *isInt = 0;
    if (!strcmp(type, "float")) return 1;
    if (!strcmp(type, "vec2")) return 2;
    if (!strcmp(type, "vec3")) return 3;
    if (!strcmp(type, "vec4")) return 4;
    *isInt = 1;
    if (!strcmp(type, "int") || !strcmp(type, "bool")) return 1;
    if (!strcmp(type, "ivec2") || !strcmp(type, "bvec2")) return 2;
    if (!strcmp(type, "ivec3") || !strcmp(type, "bvec3")) return 3;
    if (!strcmp(type, "ivec4") || !strcmp(type, "bvec4")) return 4;
    return 0;
}

// The numbers of a constant like "vec3(0.3, 0.59, 0.11)", "1.0" or "vec2(1.0)": how many there were, or -1 when the
// value is not a plain list of numbers (then the uniform starts at zero, as a uniform without a value does)
static int ko_numbers(const char *from, const char *to, float *out, int max)
{
    int n = 0;
    const char *p = from;
    while (p < to) {
        if (isalpha((unsigned char)*p) || *p == '_') {
            // (a name, "vec3" with its digit among them: skipped whole)
            while (p < to && (isalnum((unsigned char)*p) || *p == '_')) p++;
        } else if (isdigit((unsigned char)*p) || ((*p == '-' || *p == '+' || *p == '.') && p + 1 < to &&
                                                  (isdigit((unsigned char)p[1]) || p[1] == '.'))) {
            char *end;
            float f = strtof(p, &end);
            if (end == p) return -1;
            if (n < max) out[n] = f;
            n++;
            p = end;
            if (p < to && (*p == 'f' || *p == 'F')) p++;
        } else if (*p == '*' || *p == '/' || (*p == '-' && n > 0)) {
            return -1;   // (an expression: not taken)
        } else {
            p++;
        }
    }
    return n;
}

static int ko_ident(char c)
{
    return isalnum((unsigned char)c) || c == '_';
}

#define KO_MAX_LOOP_UNIFORMS 16

typedef struct {
    char name[64];
    size_t declared;   // where its declaration ends: the uses come after it
    int loops;         // the loop headers that name it
    int cap;           // 0: left as it is
} ko_loop_uniform;

// A fragment shader whose loops are bound by float uniforms, rewritten with each of them as min(name, cap) after its
// declaration; NULL when there is nothing to do (a vertex shader, no such loop, the caps set to 0)
static char *ko_cap_loops(const char *src)
{
    static int one = -1, nested = -1;
    if (one < 0) {
        int a = 8, b = 3;
        const char *env = getenv("KOSTKA_LOOP_CAPS");
        if (env && sscanf(env, "%d,%d", &a, &b) == 1) b = a;
        one = a < 0 ? 0 : a > 999 ? 999 : a;
        nested = b < 0 ? 0 : b > 999 ? 999 : b;
    }
    if ((!one && !nested) || (!strstr(src, "gl_FragColor") && !strstr(src, "gl_FragData"))) return NULL;

    // the float uniforms
    ko_loop_uniform u[KO_MAX_LOOP_UNIFORMS];
    int count = 0;
    for (const char *p = src; (p = strstr(p, "uniform")) != NULL; p += 7) {
        if ((p > src && ko_ident(p[-1])) || !isspace((unsigned char)p[7])) continue;
        const char *q = p + 7;
        while (isspace((unsigned char)*q)) q++;
        if (!strncmp(q, "lowp", 4) || !strncmp(q, "mediump", 7) || !strncmp(q, "highp", 5)) {
            while (*q && !isspace((unsigned char)*q)) q++;
            while (isspace((unsigned char)*q)) q++;
        }
        if (strncmp(q, "float", 5) || ko_ident(q[5])) continue;
        q += 5;
        while (isspace((unsigned char)*q)) q++;
        size_t n = 0;
        while (ko_ident(q[n])) n++;
        const char *semicolon = strchr(q + n, ';');
        if (!semicolon) break;
        if (!n || n >= sizeof u[0].name || count == KO_MAX_LOOP_UNIFORMS) continue;
        memcpy(u[count].name, q, n);
        u[count].name[n] = 0;
        u[count].declared = (size_t)(semicolon + 1 - src);
        u[count].loops = u[count].cap = 0;
        count++;
    }

    // the loops' headers, "for (...)", that name them
    for (const char *p = src; (p = strstr(p, "for")) != NULL; p += 3) {
        if ((p > src && ko_ident(p[-1])) || ko_ident(p[3])) continue;
        const char *open = p + 3;
        while (isspace((unsigned char)*open)) open++;
        if (*open != '(') continue;
        const char *close = open;
        int depth = 0;
        for (; *close; close++) {
            if (*close == '(') depth++;
            else if (*close == ')' && --depth == 0) break;
        }
        if (!*close) break;
        for (int i = 0; i < count; i++) {
            size_t n = strlen(u[i].name);
            for (const char *t = open; (t = strstr(t, u[i].name)) != NULL && t < close; t += n) {
                if (!ko_ident(t[-1]) && !ko_ident(t[n])) {
                    u[i].loops++;
                    break;
                }
            }
        }
    }
    int any = 0;
    for (int i = 0; i < count; i++) {
        if (u[i].loops) u[i].cap = u[i].loops > 1 ? nested : one;
        if (u[i].cap) any = 1;
    }
    if (!any) return NULL;

    // each use after the declaration becomes min(name, cap)
    size_t size = strlen(src) + 1;
    for (const char *p = src; *p; p++) {
        if (!(isalpha((unsigned char)*p) || *p == '_') || (p > src && ko_ident(p[-1]))) continue;
        size_t n = 0;
        while (ko_ident(p[n])) n++;
        for (int i = 0; i < count; i++)
            if (u[i].cap && (size_t)(p - src) >= u[i].declared && n == strlen(u[i].name) && !strncmp(p, u[i].name, n))
                size += 16;   // ("min(" "," "999" ".0)")
        p += n - 1;
    }
    char *out = malloc(size);
    if (!out) return NULL;
    char *o = out;
    for (const char *p = src; *p;) {
        if ((isalpha((unsigned char)*p) || *p == '_') && !(p > src && ko_ident(p[-1]))) {
            size_t n = 0;
            while (ko_ident(p[n])) n++;
            int capped = -1;
            for (int i = 0; i < count && capped < 0; i++)
                if (u[i].cap && (size_t)(p - src) >= u[i].declared && n == strlen(u[i].name) && !strncmp(p, u[i].name, n))
                    capped = i;
            if (capped >= 0) {
                o += sprintf(o, "min(%s,%d.0)", u[capped].name, u[capped].cap);
            } else {
                memcpy(o, p, n);
                o += n;
            }
            p += n;
        } else {
            *o++ = *p++;
        }
    }
    *o = 0;
    for (int i = 0; i < count; i++)
        if (u[i].cap) fprintf(stderr, "Kostka: a fragment shader's loops over %s go to at most %d\n", u[i].name, u[i].cap);
    return out;
}

static ko_shader_inits *ko_shader_entry(ko_uint shader, int create)
{
    ko_shader_inits *free_slot = NULL;
    for (int i = 0; i < KO_MAX_SHADERS; i++) {
        if (g_shaders[i].shader == shader) return &g_shaders[i];
        if (!g_shaders[i].shader && !free_slot) free_slot = &g_shaders[i];
    }
    if (!create || !free_slot) return NULL;
    memset(free_slot, 0, sizeof *free_slot);
    free_slot->shader = shader;
    return free_slot;
}

static void ko_glShaderSource(ko_uint shader, int count, const char *const *strings, const int *lengths)
{
    size_t total = 0;
    for (int i = 0; i < count; i++) total += (lengths && lengths[i] >= 0) ? (size_t)lengths[i] : strlen(strings[i]);
    char *src = malloc(total + 1);
    if (!src) {
        g_shader_source(shader, count, strings, lengths);
        return;
    }
    size_t at = 0;
    for (int i = 0; i < count; i++) {
        size_t len = (lengths && lengths[i] >= 0) ? (size_t)lengths[i] : strlen(strings[i]);
        memcpy(src + at, strings[i], len);
        at += len;
    }
    src[at] = 0;

    ko_shader_inits *entry = ko_shader_entry(shader, 0);
    if (entry) entry->count = 0;
    int found = 0;
    char *p = src;
    while ((p = strstr(p, "uniform")) != NULL) {
        char *start = p;
        p += 7;
        if ((start > src && (isalnum((unsigned char)start[-1]) || start[-1] == '_')) || !isspace((unsigned char)*p)) continue;
        // uniform <type> <name> [= <value>] ;
        char type[16], name[64];
        char *q = p;
        while (isspace((unsigned char)*q)) q++;
        if (!strncmp(q, "lowp", 4) || !strncmp(q, "mediump", 7) || !strncmp(q, "highp", 5)) {
            while (*q && !isspace((unsigned char)*q)) q++;
            while (isspace((unsigned char)*q)) q++;
        }
        int n = 0;
        while ((isalnum((unsigned char)*q) || *q == '_') && n < (int)sizeof type - 1) type[n++] = *q++;
        type[n] = 0;
        while (isspace((unsigned char)*q)) q++;
        n = 0;
        while ((isalnum((unsigned char)*q) || *q == '_') && n < (int)sizeof name - 1) name[n++] = *q++;
        name[n] = 0;
        while (isspace((unsigned char)*q)) q++;
        if (*q != '=' || !type[0] || !name[0]) continue;
        char *semicolon = strchr(q, ';');
        if (!semicolon) break;
        int isInt;
        int components = ko_components(type, &isInt);
        float v[4];
        int numbers = components ? ko_numbers(q + 1, semicolon, v, 4) : -1;
        if (numbers == 1 && components > 1) {
            for (int k = 1; k < components; k++) v[k] = v[0];
            numbers = components;
        }
        if (numbers == components && components > 0) {
            if (!entry) entry = ko_shader_entry(shader, 1);
            if (entry && entry->count < KO_MAX_INITS) {
                ko_init *init = &entry->inits[entry->count++];
                strcpy(init->name, name);
                init->components = components;
                init->isInt = isInt;
                memcpy(init->v, v, sizeof v);
            }
        }
        // (the value comes out of the source: "uniform vec3 Gray = vec3(...);" becomes "uniform vec3 Gray;")
        memset(q, ' ', (size_t)(semicolon - q));
        found = 1;
        p = semicolon;
    }
    char *capped = ko_cap_loops(src);
    if (capped) {
        free(src);
        src = capped;
        found = 1;
    }
    if (found) {
        const char *one = src;
        g_shader_source(shader, 1, &one, NULL);
    } else {
        g_shader_source(shader, count, strings, lengths);
    }
    free(src);
}

static ko_program_shaders *ko_program_entry(ko_uint program, int create)
{
    ko_program_shaders *free_slot = NULL;
    for (int i = 0; i < KO_MAX_PROGRAMS; i++) {
        if (g_programs[i].program == program) return &g_programs[i];
        if (!g_programs[i].program && !free_slot) free_slot = &g_programs[i];
    }
    if (!create || !free_slot) return NULL;
    memset(free_slot, 0, sizeof *free_slot);
    free_slot->program = program;
    return free_slot;
}

static void ko_glAttachShader(ko_uint program, ko_uint shader)
{
    g_attach(program, shader);
    ko_program_shaders *entry = ko_program_entry(program, 1);
    if (entry && entry->count < 8) entry->shaders[entry->count++] = shader;
}

static void ko_glLinkProgram(ko_uint program)
{
    g_link(program);
    ko_program_shaders *entry = ko_program_entry(program, 0);
    if (!entry) return;
    static ko_location_t location;
    static ko_uniformfv_t uniform[5];
    static ko_uniformiv_t uniformi[5];
    static ko_one_t use;
    static ko_getiv_t getiv;
    if (!location) {
        location = (ko_location_t)ko_gl("glGetUniformLocation");
        use = (ko_one_t)ko_gl("glUseProgram");
        getiv = (ko_getiv_t)ko_gl("glGetIntegerv");
        const char *f[] = { NULL, "glUniform1fv", "glUniform2fv", "glUniform3fv", "glUniform4fv" };
        const char *iv[] = { NULL, "glUniform1iv", "glUniform2iv", "glUniform3iv", "glUniform4iv" };
        for (int i = 1; i <= 4; i++) {
            uniform[i] = (ko_uniformfv_t)ko_gl(f[i]);
            uniformi[i] = (ko_uniformiv_t)ko_gl(iv[i]);
        }
    }
    if (!location || !use || !getiv) return;
    int previous = 0, used = 0;
    for (int s = 0; s < entry->count; s++) {
        ko_shader_inits *inits = ko_shader_entry(entry->shaders[s], 0);
        if (!inits) continue;
        for (int i = 0; i < inits->count; i++) {
            ko_init *init = &inits->inits[i];
            int at = location(program, init->name);
            if (at < 0) continue;
            if (!used) {
                getiv(KO_GL_CURRENT_PROGRAM, &previous);
                use(program);
                used = 1;
            }
            if (init->isInt) {
                int iv[4];
                for (int k = 0; k < 4; k++) iv[k] = (int)init->v[k];
                if (uniformi[init->components]) uniformi[init->components](at, 1, iv);
            } else if (uniform[init->components]) {
                uniform[init->components](at, 1, init->v);
            }
        }
    }
    if (used) use((ko_uint)previous);
}

static void ko_glDeleteShader(ko_uint shader)
{
    g_delete_shader(shader);
    ko_shader_inits *entry = ko_shader_entry(shader, 0);
    if (entry) memset(entry, 0, sizeof *entry);
}

static void ko_glDeleteProgram(ko_uint program)
{
    g_delete_program(program);
    ko_program_shaders *entry = ko_program_entry(program, 0);
    if (entry) memset(entry, 0, sizeof *entry);
}

void *ko_glsl_wrap(const char *name, void *real)
{
    if (!real) return NULL;
    if (!strcmp(name, "glShaderSource") || !strcmp(name, "glShaderSourceARB")) {
        g_shader_source = (ko_shader_source_t)real;
        return (void *)ko_glShaderSource;
    }
    if (!strcmp(name, "glAttachShader") || !strcmp(name, "glAttachObjectARB")) {
        g_attach = (ko_attach_t)real;
        return (void *)ko_glAttachShader;
    }
    if (!strcmp(name, "glLinkProgram") || !strcmp(name, "glLinkProgramARB")) {
        g_link = (ko_one_t)real;
        return (void *)ko_glLinkProgram;
    }
    if (!strcmp(name, "glDeleteShader")) {
        g_delete_shader = (ko_one_t)real;
        return (void *)ko_glDeleteShader;
    }
    if (!strcmp(name, "glDeleteProgram")) {
        g_delete_program = (ko_one_t)real;
        return (void *)ko_glDeleteProgram;
    }
    return NULL;
}
