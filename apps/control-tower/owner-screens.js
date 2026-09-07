if (typeof window !== 'undefined' && typeof document !== 'undefined') {
window.PandorasOwnerScreens = Object.freeze({
  ...window.PandorasOwnerScreenCore,
  ...window.PandorasOwnerScreenActivity,
  ...window.PandorasOwnerScreenMore,
  ...window.PandorasOwnerExperience,
  ...window.PandorasOwnerProjectWorkspace,
  ...window.PandorasOwnerProfessional,
});
}
