package doomdb.mle.engine;

/**
 * Property test for the recursive-to-iterative sight BSP transformation.
 *
 * The model checks result, leaf visitation order, early termination, and the
 * N+1 stack bound over deterministic random full binary trees. The production
 * differential still exercises Mocha's real nodes; this closes the generic
 * traversal transformation independently of any accepted route.
 */
public final class IterativeBspTraversalPropertyTest {
  private static int randomState = 0x5a17c9e3;
  private static int nodeCount;
  private static int leafCount;
  private static int[][] children;
  private static int[] startSide;
  private static int[] endSide;
  private static boolean[] leafPass;
  private static int[] recursiveVisits;
  private static int[] iterativeVisits;
  private static int recursiveVisitCount;
  private static int iterativeVisitCount;
  private static int maxStack;
  private static int checksum = 0x13579bdf;

  private IterativeBspTraversalPropertyTest() {}

  private static int random() {
    int value = randomState;
    value ^= value << 13;
    value ^= value >>> 17;
    value ^= value << 5;
    randomState = value;
    return value;
  }

  private static int bounded(int bound) {
    return (random() & 0x7fffffff) % bound;
  }

  private static int buildTree(int internalNodes) {
    if (internalNodes == 0) {
      return ~leafCount++;
    }
    int node = nodeCount++;
    int leftNodes = bounded(internalNodes);
    children[node][0] = buildTree(leftNodes);
    children[node][1] = buildTree(internalNodes - 1 - leftNodes);
    return node;
  }

  private static boolean recursive(int current) {
    if (current < 0) {
      int leaf = ~current;
      recursiveVisits[recursiveVisitCount++] = leaf;
      return leafPass[leaf];
    }
    int side = startSide[current];
    if (side == 2) side = 0;
    if (!recursive(children[current][side])) return false;
    if (side == endSide[current]) return true;
    return recursive(children[current][side ^ 1]);
  }

  private static boolean iterative(int root) {
    int[] stack = new int[nodeCount + 1];
    int size = 0;
    stack[size++] = root;
    while (size > 0) {
      int current = stack[--size];
      if (current < 0) {
        int leaf = ~current;
        iterativeVisits[iterativeVisitCount++] = leaf;
        if (!leafPass[leaf]) return false;
        continue;
      }
      int side = startSide[current];
      if (side == 2) side = 0;
      if (side != endSide[current]) {
        stack[size++] = children[current][side ^ 1];
      }
      stack[size++] = children[current][side];
      if (size > maxStack) maxStack = size;
      if (size > nodeCount + 1) {
        throw new AssertionError("iterative BSP stack exceeded N+1");
      }
    }
    return true;
  }

  private static void exercise(int internalNodes, int queries) {
    children = new int[Math.max(1, internalNodes)][2];
    startSide = new int[Math.max(1, internalNodes)];
    endSide = new int[Math.max(1, internalNodes)];
    leafPass = new boolean[internalNodes + 1];
    recursiveVisits = new int[internalNodes + 1];
    iterativeVisits = new int[internalNodes + 1];
    nodeCount = 0;
    leafCount = 0;
    int root = buildTree(internalNodes);
    if (nodeCount != internalNodes || leafCount != internalNodes + 1) {
      throw new AssertionError("invalid generated full binary tree");
    }
    for (int query = 0; query < queries; query++) {
      for (int node = 0; node < nodeCount; node++) {
        // DivlineSide returns 2 for an endpoint exactly on the partition.
        // Mocha normalizes that result only for the start point.
        startSide[node] = bounded(3);
        endSide[node] = bounded(3);
      }
      for (int leaf = 0; leaf < leafCount; leaf++) {
        leafPass[leaf] = bounded(5) != 0;
      }
      recursiveVisitCount = 0;
      iterativeVisitCount = 0;
      boolean expected = recursive(root);
      boolean actual = iterative(root);
      if (expected != actual || recursiveVisitCount != iterativeVisitCount) {
        throw new AssertionError("BSP traversal result/length mismatch");
      }
      for (int visit = 0; visit < recursiveVisitCount; visit++) {
        if (recursiveVisits[visit] != iterativeVisits[visit]) {
          throw new AssertionError("BSP leaf visitation order mismatch");
        }
        checksum = checksum * 33 + recursiveVisits[visit];
      }
      checksum = checksum * 33 + (actual ? 1 : 0);
    }
  }

  public static void main(String[] args) {
    int cases = 0;
    for (int tree = 0; tree < 2000; tree++) {
      exercise(bounded(64), 32);
      cases += 32;
    }
    exercise(255, 256);
    cases += 256;
    System.out.println(
        "PASS ITERATIVE_BSP_TRAVERSAL_PROPERTY cases=" + cases
        + " max_stack=" + maxStack + " checksum=" + checksum);
  }
}
