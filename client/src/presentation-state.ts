export type PresentationMode = 'GAME' | 'DEAD' | 'MENU' | 'AUTOMAP' | 'INTERMISSION';

export class PresentationState {
  loading = true;
  mode: PresentationMode = 'GAME';
  muted = false;
  visible = document.visibilityState === 'visible';

  setMode(value: string): void {
    const normalized = value.toUpperCase();
    if (normalized === 'GAME' || normalized === 'DEAD' || normalized === 'MENU' ||
        normalized === 'AUTOMAP' || normalized === 'INTERMISSION') {
      this.mode = normalized;
    }
  }
}
