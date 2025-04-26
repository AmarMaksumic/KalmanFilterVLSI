import numpy as np
from pathlib import Path

def make_kalman_matrices(state_size=4, dt=0.001, fixed_scale=16384):
    """
    Generate Kalman matrices A, B, C, R, Q, Sigma_init, u, z for 4, 6, or 12 state systems.
    Assumes state vector contains [pos, vel] pairs per axis.
    """
    axes = state_size // 2
    A = np.zeros((state_size, state_size))
    B = np.zeros((state_size, axes))
    C = np.eye(state_size)
    R = np.eye(state_size) * 0.01
    Q = np.eye(state_size) * 0.2
    Sigma = np.eye(state_size) * 0.01
    u = np.ones((axes, 1)) * 0.5
    z = np.arange(1, state_size + 1).reshape((state_size, 1))

    # Construct A and B
    for i in range(axes):
        A[2*i][2*i] = 1
        A[2*i][2*i + 1] = dt
        A[2*i + 1][2*i + 1] = 1

        B[2*i][i] = 0.5 * dt**2
        B[2*i + 1][i] = dt

    return {
        "A_matrix.mem": A,
        "B_matrix.mem": B,
        "C_matrix.mem": C,
        "R_matrix.mem": R,
        "Q_matrix.mem": Q,
        "Sigma_prev.mem": Sigma,
        "mu_prev.mem": np.zeros((state_size, 1)),
        "u_vector.mem": u,
        "z_vector.mem": z
    }

def to_fixed_hex(matrix, scale=16384, total_elements=16):
    flat = matrix.flatten()
    scaled = np.round(flat * scale).astype(np.int32)
    return [f"{x & 0xFFFF:04X}" for x in scaled] + ["0000"] * (total_elements - len(scaled))

# Generate and write files for 4, 6, and 12 state configurations
output_dirs = {}
for N in [4, 6, 12]:
    mems = make_kalman_matrices(state_size=N)
    mem_dir = Path(f"kalman_matrices_{N}")
    mem_dir.mkdir(exist_ok=True)
    for name, mat in mems.items():
        total = N * N if mat.shape[1] != 1 else N * 4  # pad vectors to at least 16
        lines = to_fixed_hex(mat, total_elements=total)
        (mem_dir / name).write_text("\n".join(lines))
    output_dirs[f"{N}_state"] = str(mem_dir)

output_dirs
