export class PresentationState {
    loading = true;
    mode = 'GAME';
    muted = false;
    visible = document.visibilityState === 'visible';
    setMode(value) {
        const normalized = value.toUpperCase();
        if (normalized === 'GAME' || normalized === 'DEAD' || normalized === 'MENU' ||
            normalized === 'AUTOMAP' || normalized === 'INTERMISSION') {
            this.mode = normalized;
        }
    }
}
