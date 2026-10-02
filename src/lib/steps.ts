export type StepState = 'waiting' | 'active' | 'done' | 'failed'

export interface Step {
  label: string
  state: StepState
}

/** Runs one step of a multi-step process, marking it active → done (or failed). */
export async function runStep<T>(steps: Step[], i: number, work: () => Promise<T>): Promise<T> {
  steps[i]!.state = 'active'
  try {
    const result = await work()
    steps[i]!.state = 'done'
    return result
  } catch (e) {
    steps[i]!.state = 'failed'
    throw e
  }
}

export function resetSteps(steps: Step[]) {
  steps.forEach((s) => (s.state = 'waiting'))
}
