export class PresentationState {
    loading = true;
    mode = 'GAME';
    muted = false;
    focused = document.hasFocus();
    visible = document.visibilityState === 'visible';
    setMode(value) {
        const normalized = value.toUpperCase();
        if (normalized === 'GAME' || normalized === 'MENU' || normalized === 'AUTOMAP' || normalized === 'INTERMISSION') {
            this.mode = normalized;
        }
    }
}
