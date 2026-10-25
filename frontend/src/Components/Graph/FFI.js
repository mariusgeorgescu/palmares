// Cytoscape, legat de Halogen prin cel mai mic FFI care face treaba.
//
// PureScript nu poate conduce motorul de layout al lui Cytoscape și nici mutațiile lui în DOM,
// deci cele patru funcții de aici sunt singura parte imperativă a grafului. Tot ce decide CE se
// desenează — cine e nod, cine e muchie, ce scrie pe ele — stă în PureScript și se testează acolo.
//
// Fișierul e scris de la zero, nu copiat din `bjj-frontend`: acela are 399 de linii din care cele
// mai multe sunt mașinărie pentru avatare (preîncărcare, PNG în loc de SVG, fallback-uri), iar un
// graf de guvernanță n-are avatare. Ce rămânea după ștergere era mai puțin decât ce urmează.
import cytoscape from "cytoscape";

// Culorile sînt scrise aici, și NU citite din tema daisyUI, dintr-un motiv măsurat: daisyUI 5
// emite `oklch(...)`, iar parserul de culori al lui Cytoscape nu-l cunoaște. Trecute prin, dau
// nouă avertismente „The style property `background-color: oklch(…)` is invalid" și un graf fără
// culori. Hexurile de mai jos sînt luate din tema `dim`, care e singura în care rulează aplicația.
const palette = () => ({
  node: "#2a323c",
  nodeText: "#b2ccd6",
  root: "#9fe88d",
  edge: "#7d8590",
});

export const initGraph = (element) => () => {
  const c = palette();
  return cytoscape({
    container: element,
    // Fără interacțiune de tip „box select": graful e de citit, nu de editat.
    boxSelectionEnabled: false,
    autounselectify: false,
    style: [
      {
        selector: "node",
        style: {
          "background-color": c.node,
          "border-width": 2,
          "border-color": c.edge,
          label: "data(label)",
          color: c.nodeText,
          "font-size": 10,
          "text-valign": "bottom",
          "text-margin-y": 4,
          "text-wrap": "ellipsis",
          "text-max-width": 120,
          width: 28,
          height: 28,
        },
      },
      {
        // Rădăcina e lucrul despre care e graful, deci e mai mare și are culoarea primară.
        selector: "node[?isRoot]",
        style: {
          "background-color": c.root,
          "border-color": c.root,
          width: 48,
          height: 48,
          "font-size": 12,
          "font-weight": "bold",
        },
      },
      {
        selector: "edge",
        style: {
          width: 1.5,
          "line-color": c.edge,
          "target-arrow-color": c.edge,
          "target-arrow-shape": "triangle",
          "curve-style": "bezier",
          opacity: 0.6,
          label: "data(label)",
          color: c.nodeText,
          "font-size": 9,
          "text-rotation": "autorotate",
          "text-background-color": c.node,
          "text-background-opacity": 0.85,
          "text-background-padding": 2,
        },
      },
    ],
  });
};

export const setElements = (cy) => (nodes) => (edges) => () => {
  // Cytoscape măsoară containerul la `init`, iar atunci Halogen abia a pus elementul în DOM și
  // are 0x0. Fără `resize` aici, graful se desenează într-un colț de 1px indiferent cît de mare e
  // cartonul. Măsurat: container 1232x512, desen în 20x20 în stînga sus.
  cy.resize();
  cy.elements().remove();
  cy.add(nodes.map((n) => ({ group: "nodes", data: n })));
  cy.add(edges.map((e) => ({ group: "edges", data: e })));
  // `concentric` și nu `cose`: forma reală a datelor e o stea — un DRep cu delegatorii lui, un
  // profil cu atestările lui — iar un layout cu forțe o desenează ca pe un nor din care nu se mai
  // vede care e centrul. Concentric pune rădăcina în mijloc prin construcție.
  cy.layout({
    name: "concentric",
    concentric: (n) => (n.data("isRoot") ? 10 : 1),
    levelWidth: () => 1,
    minNodeSpacing: 28,
    animate: false,
  }).run();
  cy.fit(undefined, 24);
};

export const fitGraph = (cy) => () => cy.fit(undefined, 24);

export const destroyGraph = (cy) => () => cy.destroy();
