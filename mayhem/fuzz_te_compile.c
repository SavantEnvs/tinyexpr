/*
 * libFuzzer harness for tinyexpr's public compile/evaluate API.
 *
 * The input is an expression string. It is compiled with te_compile() against a
 * fixed set of bound variables, functions and closures (so find_lookup and the
 * TE_FUNCTIONn / TE_CLOSUREn call paths are reachable), then evaluated with
 * te_eval() and released with te_free(). Input length is not capped, so deep
 * nesting reaches the parser's recursion limit (TE_MAX_DEPTH, upstream a851f2b).
 *
 * State kept across inputs: the bound doubles x/y/z are reset per input, and the
 * closure context is read-only. Nothing else is global.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "tinyexpr.h"

static double f0(void) { return 3.0; }
static double f2(double a, double b) { return a * b + 1.0; }
static double f3(double a, double b, double c) { return a - b + c; }
static double f7(double a, double b, double c, double d, double e, double f, double g) {
    return a + b + c + d + e + f + g;
}
static double c0(void *ctx) { return ((const double *)ctx)[0]; }
static double c1(void *ctx, double a) { return ((const double *)ctx)[1] * a; }
static double c2(void *ctx, double a, double b) { return ((const double *)ctx)[2] + a - b; }

static const double closure_ctx[3] = {1.5, 2.0, -4.0};

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    char *expr = (char *)malloc(size + 1);
    if (!expr) return 0;
    memcpy(expr, data, size);
    expr[size] = '\0';

    double x = 2.0, y = -3.5, z = 0.0;
    te_variable vars[] = {
        {"x", &x, TE_VARIABLE, NULL},
        {"y", &y, TE_VARIABLE, NULL},
        {"z_1", &z, TE_VARIABLE, NULL},
        {"f0", (const void *)f0, TE_FUNCTION0 | TE_FLAG_PURE, NULL},
        {"f2", (const void *)f2, TE_FUNCTION2 | TE_FLAG_PURE, NULL},
        {"f3", (const void *)f3, TE_FUNCTION3, NULL},
        {"f7", (const void *)f7, TE_FUNCTION7 | TE_FLAG_PURE, NULL},
        {"c0", (const void *)c0, TE_CLOSURE0, (void *)closure_ctx},
        {"c1", (const void *)c1, TE_CLOSURE1 | TE_FLAG_PURE, (void *)closure_ctx},
        {"c2", (const void *)c2, TE_CLOSURE2, (void *)closure_ctx},
    };

    int err = 0;
    te_expr *e = te_compile(expr, vars, (int)(sizeof(vars) / sizeof(vars[0])), &err);
    if (e) {
        volatile double r = te_eval(e);
        (void)r;
        te_free(e);
    }
    free(expr);
    return 0;
}
