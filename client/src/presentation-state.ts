export type PresentationMode = 'GAME' | 'MENU' | 'AUTOMAP' | 'INTERMISSION';

export class PresentationState {
  loading = true;
  mode: PresentationMode = 'GAME';
  muted = false;
  visible = document.visibilityState === 'visible';

  setMode(value: string): void {
    const normalized = value.toUpperCase();
    if (normalized === 'GAME' || normalized === 'MENU' || normalized === 'AUTOMAP' || normalized === 'INTERMISSION') {
      this.mode = normalized;
    }
  }
}
