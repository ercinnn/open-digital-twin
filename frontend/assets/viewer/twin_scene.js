/*
 * Open Digital Twin - Three.js scene bridge.
 *
 * Flutter -> Three ("FlutterToThree"):
 *   window.FlutterToThree.receive(json)  (WebViews, via runJavaScript/executeScript)
 *   window.postMessage(json)              (Flutter Web iframe)
 *   json = {"channel":"FlutterToThree","type":<command>,"payload":{...}}
 *   commands: load_model{url}, set_statuses{statuses:{mesh_node_id:status}},
 *             select_node{mesh_node_id|null, focus:bool}, focus_node{mesh_node_id},
 *             focus_nodes{mesh_node_ids:[...]}, reset_camera{},
 *             set_color_mode{mode:"status"|"material"|"overlay"},
 *             set_overlay{colors:{mesh_node_id:"#rrggbb"}}            (overlay color mode; others dimmed)
 *             set_placements{placements:{mesh_node_id:{mode:"home"|"hidden"|"area", area, ghost}}}
 *                 moves block meshes to a yard area node (halls hosting blocks turn x-ray)
 *             set_markers{markers:[{id, mesh_node_id, u, v, w, color, label}]}
 *                 pins at a normalized point (u: x, v: z, w: height) of the node's bounding box
 *             set_highlights{highlights:{mesh_node_id:"#rrggbb"}}       (blinking emissive)
 *             set_labels{labels:{mesh_node_id:text}, visible:bool}
 *             set_hidden{mesh_node_ids:[...]}                          (layer filter)
 *
 * Three -> Flutter ("ThreeToFlutter"):
 *   json = {"channel":"ThreeToFlutter","type":<event>,"payload":{...}}
 *   events: viewer_ready, model_progress{loaded,total}, model_loaded{mesh_node_ids,url},
 *           model_error{message}, node_selected{mesh_node_id|null}, marker_selected{id},
 *           viewer_error{message}
 */
(function () {
  'use strict';

  var STATUS_COLORS = {
    normal: 0x22c55e,
    in_progress: 0x3b82f6,
    warning: 0xf59e0b,
    alert: 0xef4444,
  };

  // ------------------------------------------------------------------ transport
  function emit(type, payload) {
    var msg = JSON.stringify({ channel: 'ThreeToFlutter', type: type, payload: payload || {} });
    try {
      if (window.ThreeToFlutter && typeof window.ThreeToFlutter.postMessage === 'function') {
        window.ThreeToFlutter.postMessage(msg); // webview_flutter JavaScriptChannel
      } else if (window.chrome && window.chrome.webview && window.chrome.webview.postMessage) {
        window.chrome.webview.postMessage(msg); // webview_windows (WebView2)
      } else if (window.parent && window.parent !== window) {
        window.parent.postMessage(msg, '*'); // Flutter Web iframe
      }
    } catch (e) {
      console.error('[twin_scene] emit failed', e);
    }
  }

  var pending = [];
  var handler = null;

  function dispatch(raw) {
    var msg = raw;
    if (typeof raw === 'string') {
      try { msg = JSON.parse(raw); } catch (e) { return; }
    }
    if (!msg || msg.channel !== 'FlutterToThree') return;
    if (handler) handler(msg); else pending.push(msg);
  }

  window.FlutterToThree = { receive: dispatch };
  window.addEventListener('message', function (ev) { dispatch(ev.data); });

  function showError(text) {
    var el = document.getElementById('error');
    el.textContent = text;
    el.style.display = 'flex';
  }

  // ------------------------------------------------------------------ scene
  async function boot() {
    var THREE = await import('three');
    var OrbitControls = (await import('three/addons/controls/OrbitControls.js')).OrbitControls;
    var GLTFLoader = (await import('three/addons/loaders/GLTFLoader.js')).GLTFLoader;
    var RoomEnvironment = (await import('three/addons/environments/RoomEnvironment.js')).RoomEnvironment;

    var container = document.getElementById('viewport');
    var renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setSize(container.clientWidth, container.clientHeight);
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.0;
    container.appendChild(renderer.domElement);

    var scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0b1220);
    var pmrem = new THREE.PMREMGenerator(renderer);
    scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;

    var camera = new THREE.PerspectiveCamera(45, container.clientWidth / Math.max(1, container.clientHeight), 0.01, 5000);
    camera.position.set(9, 12.5, 11);

    var controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.08;
    controls.screenSpacePanning = true;

    scene.add(new THREE.HemisphereLight(0xdbeafe, 0x1e293b, 0.6));
    var sun = new THREE.DirectionalLight(0xffffff, 1.6);
    sun.position.set(12, 20, 8);
    scene.add(sun);

    var grid = new THREE.GridHelper(40, 40, 0x334155, 0x1e293b);
    grid.material.transparent = true;
    grid.material.opacity = 0.6;
    scene.add(grid);

    var loader = new GLTFLoader();
    var modelRoot = null;
    var nodes = new Map();        // mesh_node_id -> Object3D
    var pickables = [];           // meshes eligible for raycasting
    var statuses = {};            // mesh_node_id -> status
    var colorMode = 'status';
    var overlayColors = {};       // mesh_node_id -> '#rrggbb' (overlay mode)
    var placements = {};          // mesh_node_id -> {mode, area, ghost}
    var xrayIds = new Set();      // area nodes currently hosting placed blocks
    var hiddenIds = new Set();    // layer filter
    var highlights = {};          // mesh_node_id -> THREE.Color (blinking)
    var labelTexts = {};          // mesh_node_id -> text
    var labelsVisible = false;
    var markerSpecs = [];         // [{id, mesh_node_id, u, v, w, color, label}]
    var markerGroup = new THREE.Group();
    var labelGroup = new THREE.Group();
    scene.add(markerGroup);
    scene.add(labelGroup);
    var selectedId = null;
    var selectionBox = null;
    var homeView = null;
    var cameraTween = null;
    var loadToken = 0;
    var DIM_COLOR = 0x334155;

    function nodeIdFor(obj) {
      while (obj) {
        if (obj.userData && typeof obj.userData.mesh_node_id === 'string') return obj.userData.mesh_node_id;
        if (/^NODE_/.test(obj.name || '')) return obj.name;
        obj = obj.parent;
      }
      return null;
    }

    function isContext(obj) {
      while (obj) {
        if (/^CTX_/.test(obj.name || '')) return true;
        obj = obj.parent;
      }
      return false;
    }

    function isShown(obj) {
      while (obj) {
        if (!obj.visible) return false;
        obj = obj.parent;
      }
      return true;
    }

    // Ghost opacity for CTX_ geometry; a glTF extras value `ctx_opacity` (0..1) overrides the default.
    function contextOpacity(obj) {
      while (obj) {
        var v = obj.userData ? obj.userData.ctx_opacity : undefined;
        if (typeof v === 'number' && v > 0) return Math.min(v, 1);
        obj = obj.parent;
      }
      return 0.16;
    }

    function forEachMesh(root, fn) {
      root.traverse(function (child) { if (child.isMesh) fn(child); });
    }

    function parseColor(value, fallback) {
      try { return new THREE.Color(value); } catch (e) { return new THREE.Color(fallback); }
    }

    function clamp01(v, fallback) {
      return typeof v === 'number' && isFinite(v) ? Math.min(1, Math.max(0, v)) : fallback;
    }

    function disposeSprites(group) {
      while (group.children.length) {
        var sprite = group.children.pop();
        if (sprite.material.map) sprite.material.map.dispose();
        sprite.material.dispose();
      }
    }

    function disposeModel() {
      if (!modelRoot) return;
      scene.remove(modelRoot);
      modelRoot.traverse(function (child) {
        if (child.isMesh) {
          child.geometry.dispose();
          var mats = Array.isArray(child.material) ? child.material : [child.material];
          mats.forEach(function (m) { m.dispose(); });
          if (child.userData.originalMaterial) child.userData.originalMaterial.dispose();
        }
      });
      modelRoot = null;
      nodes.clear();
      pickables = [];
      disposeSprites(markerGroup);
      disposeSprites(labelGroup);
      clearSelectionBox();
    }

    // -------------------------------------------------------------- appearance
    function applyAppearance() {
      nodes.forEach(function (node, id) {
        var status = statuses[id];
        var placement = placements[id];
        var ghost = !!(placement && placement.mode === 'area' && placement.ghost);
        var xray = xrayIds.has(id);
        node.visible = !hiddenIds.has(id) && !(placement && placement.mode === 'hidden');
        forEachMesh(node, function (mesh) {
          var original = mesh.userData.originalMaterial;
          var mat = mesh.material;
          if (colorMode === 'status' && status && STATUS_COLORS[status] !== undefined) {
            mat.color.setHex(STATUS_COLORS[status]);
            mat.metalness = Math.min(original.metalness !== undefined ? original.metalness : 0, 0.35);
            mat.roughness = 0.55;
          } else if (colorMode === 'overlay') {
            mat.color.copy(overlayColors[id] ? parseColor(overlayColors[id], DIM_COLOR) : new THREE.Color(DIM_COLOR));
            mat.metalness = 0.1;
            mat.roughness = 0.7;
          } else {
            mat.color.copy(original.color);
            if (original.metalness !== undefined) mat.metalness = original.metalness;
            if (original.roughness !== undefined) mat.roughness = original.roughness;
          }
          var opacity = xray ? 0.22 : (ghost ? 0.45 : (original.transparent ? original.opacity : 1));
          mat.transparent = opacity < 1;
          mat.opacity = opacity;
          mat.depthWrite = opacity >= 1;
          mesh.renderOrder = xray ? 2 : 0;
          if (mat.emissive) mat.emissive.setHex(0x000000);
          mat.needsUpdate = true;
        });
      });
    }

    function clearSelectionBox() {
      if (selectionBox) {
        scene.remove(selectionBox);
        selectionBox.geometry.dispose();
        selectionBox.material.dispose();
        selectionBox = null;
      }
    }

    function updateSelection() {
      clearSelectionBox();
      var node = selectedId ? nodes.get(selectedId) : null;
      if (!node || !node.visible) return;
      selectionBox = new THREE.BoxHelper(node, 0x22d3ee);
      selectionBox.material.depthTest = false;
      selectionBox.material.transparent = true;
      selectionBox.renderOrder = 999;
      scene.add(selectionBox);
    }

    // -------------------------------------------------------------- block placement
    // Blocks are modelled at their erected position. A placement moves the node so
    // that its bounding-box bottom centre lands on a slot inside the area node.
    function homeBox(node) {
      if (!node.userData.homeBox) {
        var saved = node.position.clone();
        node.position.copy(node.userData.homePosition);
        node.updateMatrixWorld(true);
        node.userData.homeBox = new THREE.Box3().setFromObject(node);
        node.position.copy(saved);
        node.updateMatrixWorld(true);
      }
      return node.userData.homeBox;
    }

    function startMove(node, target, animate) {
      if (!animate) {
        node.userData.move = null;
        node.position.copy(target);
        return;
      }
      if (node.position.distanceToSquared(target) < 1e-6) {
        node.userData.move = null;
        return;
      }
      node.userData.move = { from: node.position.clone(), to: target.clone(), start: performance.now(), duration: 700 };
    }

    function applyPlacements(animate) {
      if (!modelRoot) return;
      var groups = {};
      xrayIds = new Set();
      Object.keys(placements).forEach(function (id) {
        var p = placements[id];
        if (p && p.mode === 'area' && nodes.has(id) && nodes.has(p.area)) {
          (groups[p.area] = groups[p.area] || []).push(id);
        }
      });
      nodes.forEach(function (node, id) {
        var p = placements[id];
        if (!p || p.mode !== 'area' || !nodes.has(p.area)) startMove(node, node.userData.homePosition, animate);
      });
      Object.keys(groups).forEach(function (areaId) {
        var areaBox = homeBox(nodes.get(areaId));
        var center = areaBox.getCenter(new THREE.Vector3());
        var size = areaBox.getSize(new THREE.Vector3());
        var alongX = size.x >= size.z;
        var ids = groups[areaId].sort();
        var gap = 6;
        var lengths = ids.map(function (id) {
          var s = homeBox(nodes.get(id)).getSize(new THREE.Vector3());
          return alongX ? s.x : s.z;
        });
        var total = lengths.reduce(function (a, b) { return a + b; }, 0) + gap * (ids.length - 1);
        var cursor = -total / 2;
        var groundY = Math.max(areaBox.min.y, 0) + 0.3;
        ids.forEach(function (id, i) {
          var node = nodes.get(id);
          var box = homeBox(node);
          var bottomCenter = new THREE.Vector3((box.min.x + box.max.x) / 2, box.min.y, (box.min.z + box.max.z) / 2);
          var slot = cursor + lengths[i] / 2;
          cursor += lengths[i] + gap;
          var target = new THREE.Vector3(
            alongX ? center.x + slot : center.x,
            groundY,
            alongX ? center.z : center.z + slot
          );
          startMove(node, node.userData.homePosition.clone().add(target.sub(bottomCenter)), animate);
        });
        xrayIds.add(areaId);
      });
      applyAppearance();
      updateSelection();
    }

    // -------------------------------------------------------------- sprites (markers / labels)
    function pinTexture(color, text) {
      var canvas = document.createElement('canvas');
      canvas.width = 96;
      canvas.height = 128;
      var g = canvas.getContext('2d');
      g.fillStyle = color;
      g.strokeStyle = '#0b1220';
      g.lineWidth = 6;
      g.beginPath();
      g.arc(48, 44, 36, Math.PI, 0);
      g.quadraticCurveTo(84, 80, 48, 124);
      g.quadraticCurveTo(12, 80, 12, 44);
      g.closePath();
      g.fill();
      g.stroke();
      g.fillStyle = '#0b1220';
      g.font = 'bold 34px system-ui, sans-serif';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillText(String(text || '').slice(0, 2), 48, 46);
      var tex = new THREE.CanvasTexture(canvas);
      tex.colorSpace = THREE.SRGBColorSpace;
      return tex;
    }

    function labelTexture(text) {
      var font = '600 30px system-ui, -apple-system, "Segoe UI", Roboto, sans-serif';
      var canvas = document.createElement('canvas');
      var g = canvas.getContext('2d');
      g.font = font;
      var w = Math.ceil(g.measureText(text).width) + 28;
      canvas.width = w;
      canvas.height = 48;
      g = canvas.getContext('2d');
      g.fillStyle = 'rgba(11,18,32,0.82)';
      g.strokeStyle = 'rgba(34,211,238,0.7)';
      g.lineWidth = 2;
      g.beginPath();
      if (g.roundRect) g.roundRect(1, 1, w - 2, 46, 10); else g.rect(1, 1, w - 2, 46);
      g.fill();
      g.stroke();
      g.font = font;
      g.fillStyle = '#e2e8f0';
      g.textBaseline = 'middle';
      g.fillText(text, 14, 25);
      var tex = new THREE.CanvasTexture(canvas);
      tex.colorSpace = THREE.SRGBColorSpace;
      return { texture: tex, aspect: w / 48 };
    }

    function rebuildMarkers() {
      disposeSprites(markerGroup);
      markerSpecs.forEach(function (m) {
        if (!nodes.has(m.mesh_node_id)) return;
        var sprite = new THREE.Sprite(new THREE.SpriteMaterial({
          map: pinTexture(m.color || '#f59e0b', m.label), depthTest: false, transparent: true, sizeAttenuation: false,
        }));
        sprite.center.set(0.5, 0);
        sprite.scale.set(0.03, 0.04, 1);
        sprite.renderOrder = 1000;
        sprite.userData.marker = m;
        markerGroup.add(sprite);
      });
      updateSpritePositions();
    }

    function rebuildLabels() {
      disposeSprites(labelGroup);
      labelGroup.visible = labelsVisible;
      if (!labelsVisible) return;
      Object.keys(labelTexts).forEach(function (id) {
        if (!nodes.has(id)) return;
        var t = labelTexture(labelTexts[id]);
        var sprite = new THREE.Sprite(new THREE.SpriteMaterial({
          map: t.texture, depthTest: false, transparent: true, sizeAttenuation: false,
        }));
        sprite.center.set(0.5, 0);
        sprite.scale.set(0.026 * t.aspect, 0.026, 1);
        sprite.renderOrder = 998;
        sprite.userData.nodeId = id;
        labelGroup.add(sprite);
      });
      updateSpritePositions();
    }

    function updateSpritePositions() {
      var boxes = {};
      function boxOf(id) {
        if (!boxes[id]) boxes[id] = new THREE.Box3().setFromObject(nodes.get(id));
        return boxes[id];
      }
      markerGroup.children.forEach(function (sprite) {
        var m = sprite.userData.marker;
        var node = nodes.get(m.mesh_node_id);
        sprite.visible = !!node && isShown(node);
        if (!sprite.visible) return;
        var b = boxOf(m.mesh_node_id);
        sprite.position.set(
          b.min.x + (b.max.x - b.min.x) * clamp01(m.u, 0.5),
          b.min.y + (b.max.y - b.min.y) * clamp01(m.w, 1),
          b.min.z + (b.max.z - b.min.z) * clamp01(m.v, 0.5)
        );
      });
      if (!labelGroup.visible) return;
      labelGroup.children.forEach(function (sprite) {
        var node = nodes.get(sprite.userData.nodeId);
        sprite.visible = !!node && isShown(node);
        if (!sprite.visible) return;
        var b = boxOf(sprite.userData.nodeId);
        sprite.position.set((b.min.x + b.max.x) / 2, b.max.y + 2, (b.min.z + b.max.z) / 2);
      });
    }

    // -------------------------------------------------------------- camera
    function frameBox(box, animate) {
      if (box.isEmpty()) return;
      var size = box.getSize(new THREE.Vector3());
      var center = box.getCenter(new THREE.Vector3());
      var radius = Math.max(size.length() / 2, 0.25);
      var fov = camera.fov * Math.PI / 180;
      var distance = (radius / Math.sin(fov / 2)) * 1.15;
      var dir = new THREE.Vector3().subVectors(camera.position, controls.target);
      if (dir.lengthSq() < 1e-6) dir.set(0.9, 1.25, 1.1);
      dir.normalize();
      var toPos = center.clone().add(dir.multiplyScalar(distance));
      camera.near = Math.max(distance / 1000, 0.005);
      camera.far = distance * 100 + 100;
      camera.updateProjectionMatrix();
      if (!animate) {
        camera.position.copy(toPos);
        controls.target.copy(center);
        controls.update();
        return;
      }
      cameraTween = {
        fromPos: camera.position.clone(), toPos: toPos,
        fromTarget: controls.target.clone(), toTarget: center,
        start: performance.now(), duration: 650,
      };
    }

    // Box of a node at the end of its current move (so focusing a moving block works).
    function nodeTargetBox(id) {
      var node = nodes.get(id);
      if (!node) return null;
      var move = node.userData.move;
      if (!move) return new THREE.Box3().setFromObject(node);
      return homeBox(node).clone().translate(move.to.clone().sub(node.userData.homePosition));
    }

    function focusNode(id) {
      var box = nodeTargetBox(id);
      if (box) frameBox(box, true);
    }

    function focusNodes(ids) {
      var box = new THREE.Box3();
      (ids || []).forEach(function (id) {
        var b = nodeTargetBox(id);
        if (b && nodes.get(id).visible) box.union(b);
      });
      if (!box.isEmpty()) frameBox(box, true);
    }

    function resetCamera() {
      if (homeView) frameBox(homeView.clone(), true);
    }

    // -------------------------------------------------------------- loading
    function loadModel(url) {
      var token = ++loadToken;
      disposeModel();
      if (!url) return;
      loader.load(
        url,
        function (gltf) {
          if (token !== loadToken) return;
          modelRoot = gltf.scene;
          modelRoot.traverse(function (child) {
            if (!child.isMesh) return;
            if (Array.isArray(child.material)) child.material = child.material[0];
            if (isContext(child)) {
              var opacity = contextOpacity(child);
              var opaque = opacity >= 0.99;
              child.material = new THREE.MeshStandardMaterial({
                color: child.material.color ? child.material.color.clone() : new THREE.Color(0xcbd5e1),
                transparent: !opaque, opacity: opaque ? 1 : opacity, depthWrite: opaque, roughness: 0.9,
              });
              child.renderOrder = opaque ? 0 : 1;
              return;
            }
            child.userData.originalMaterial = child.material;
            child.material = child.material.clone();
            var id = nodeIdFor(child);
            if (id) {
              pickables.push(child);
              var owner = child;
              while (owner.parent && nodeIdFor(owner.parent) === id) owner = owner.parent;
              if (!nodes.has(id)) nodes.set(id, owner);
            }
          });
          nodes.forEach(function (node) {
            node.userData.homePosition = node.position.clone();
            node.userData.homeBox = null;
            node.userData.move = null;
          });
          scene.add(modelRoot);
          modelRoot.updateMatrixWorld(true);

          var box = new THREE.Box3().setFromObject(modelRoot);
          homeView = box.clone();
          var size = box.getSize(new THREE.Vector3());
          grid.scale.setScalar(Math.max(1, Math.ceil(Math.max(size.x, size.z) * 1.6 / 40)));
          grid.position.set(box.getCenter(new THREE.Vector3()).x, box.min.y - 0.001, box.getCenter(new THREE.Vector3()).z);
          frameBox(box, false);
          applyPlacements(false);
          rebuildMarkers();
          rebuildLabels();
          emit('model_loaded', { url: url, mesh_node_ids: Array.from(nodes.keys()).sort() });
        },
        function (xhr) {
          if (token !== loadToken) return;
          emit('model_progress', { loaded: xhr.loaded || 0, total: xhr.total || 0 });
        },
        function (err) {
          if (token !== loadToken) return;
          emit('model_error', { message: (err && err.message) ? err.message : String(err) });
        }
      );
    }

    // -------------------------------------------------------------- picking
    var raycaster = new THREE.Raycaster();
    var pointer = new THREE.Vector2();
    var downAt = null;

    function setPointer(clientX, clientY) {
      var rect = renderer.domElement.getBoundingClientRect();
      pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
      pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
      raycaster.setFromCamera(pointer, camera);
    }

    function pickMarker() {
      var visible = markerGroup.children.filter(function (s) { return s.visible; });
      if (!visible.length) return null;
      var hits = raycaster.intersectObjects(visible, false);
      return hits.length ? hits[0].object.userData.marker : null;
    }

    function pickNode() {
      var hits = raycaster.intersectObjects(pickables, false);
      for (var i = 0; i < hits.length; i++) {
        if (isShown(hits[i].object)) return nodeIdFor(hits[i].object);
      }
      return null;
    }

    renderer.domElement.addEventListener('pointerdown', function (e) { downAt = { x: e.clientX, y: e.clientY }; });
    renderer.domElement.addEventListener('pointerup', function (e) {
      if (!downAt) return;
      var moved = Math.hypot(e.clientX - downAt.x, e.clientY - downAt.y);
      downAt = null;
      if (moved > 5 || e.button !== 0) return;
      setPointer(e.clientX, e.clientY);
      var marker = pickMarker();
      if (marker) {
        selectedId = marker.mesh_node_id;
        updateSelection();
        emit('marker_selected', { id: marker.id, mesh_node_id: marker.mesh_node_id });
        return;
      }
      selectedId = pickNode();
      updateSelection();
      emit('node_selected', { mesh_node_id: selectedId });
    });
    renderer.domElement.addEventListener('pointermove', function (e) {
      if (e.buttons) return;
      setPointer(e.clientX, e.clientY);
      renderer.domElement.style.cursor = (pickMarker() || pickNode()) ? 'pointer' : 'default';
    });

    // -------------------------------------------------------------- commands
    handler = function (msg) {
      var p = msg.payload || {};
      switch (msg.type) {
        case 'load_model': loadModel(p.url); break;
        case 'set_statuses': statuses = p.statuses || {}; applyAppearance(); break;
        case 'set_color_mode':
          colorMode = (p.mode === 'material' || p.mode === 'overlay') ? p.mode : 'status';
          applyAppearance();
          break;
        case 'set_overlay': overlayColors = p.colors || {}; applyAppearance(); break;
        case 'set_placements': placements = p.placements || {}; applyPlacements(p.animate !== false); break;
        case 'set_markers': markerSpecs = Array.isArray(p.markers) ? p.markers : []; rebuildMarkers(); break;
        case 'set_highlights':
          highlights = {};
          Object.keys(p.highlights || {}).forEach(function (id) {
            highlights[id] = parseColor(p.highlights[id], 0xf59e0b);
          });
          applyAppearance();
          break;
        case 'set_labels':
          labelTexts = p.labels || labelTexts;
          labelsVisible = !!p.visible;
          rebuildLabels();
          break;
        case 'set_hidden':
          hiddenIds = new Set(Array.isArray(p.mesh_node_ids) ? p.mesh_node_ids : []);
          applyAppearance();
          updateSelection();
          break;
        case 'select_node':
          selectedId = p.mesh_node_id || null;
          updateSelection();
          if (selectedId && p.focus) focusNode(selectedId);
          break;
        case 'focus_node': focusNode(p.mesh_node_id); break;
        case 'focus_nodes': focusNodes(p.mesh_node_ids); break;
        case 'reset_camera': resetCamera(); break;
        default: console.warn('[twin_scene] unknown command', msg.type);
      }
    };

    // -------------------------------------------------------------- loop
    function onResize() {
      var w = container.clientWidth, h = Math.max(1, container.clientHeight);
      renderer.setSize(w, h);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    }
    window.addEventListener('resize', onResize);
    if (window.ResizeObserver) new ResizeObserver(onResize).observe(container);

    var clock = new THREE.Clock();
    function animate() {
      requestAnimationFrame(animate);
      var t = clock.getElapsedTime();
      var now = performance.now();

      if (cameraTween) {
        var k = Math.min(1, (now - cameraTween.start) / cameraTween.duration);
        var e = 1 - Math.pow(1 - k, 3);
        camera.position.lerpVectors(cameraTween.fromPos, cameraTween.toPos, e);
        controls.target.lerpVectors(cameraTween.fromTarget, cameraTween.toTarget, e);
        if (k >= 1) cameraTween = null;
      }

      nodes.forEach(function (node) {
        var move = node.userData.move;
        if (!move) return;
        var mk = Math.min(1, (now - move.start) / move.duration);
        var me = mk < 0.5 ? 4 * mk * mk * mk : 1 - Math.pow(-2 * mk + 2, 3) / 2;
        node.position.lerpVectors(move.from, move.to, me);
        if (mk >= 1) node.userData.move = null;
      });
      if (markerGroup.children.length || labelGroup.visible) updateSpritePositions();

      var alertPulse = 0.25 + 0.55 * (0.5 + 0.5 * Math.sin(t * 6.0));
      var blink = 0.5 + 0.5 * Math.sin(t * 3.2);
      nodes.forEach(function (node, id) {
        var isAlert = statuses[id] === 'alert' && colorMode === 'status';
        var hl = highlights[id];
        var isSelected = id === selectedId;
        forEachMesh(node, function (mesh) {
          var em = mesh.material.emissive;
          if (!em) return;
          if (isAlert) em.setRGB(alertPulse, 0.02, 0.02);
          else if (hl) em.setRGB(hl.r * blink * 0.8, hl.g * blink * 0.8, hl.b * blink * 0.8);
          else if (isSelected) em.setRGB(0.02, 0.05, 0.06);
          else if (em.getHex() !== 0) em.setHex(0x000000);
        });
      });
      if (selectionBox) selectionBox.update();

      controls.update();
      renderer.render(scene, camera);
    }
    animate();

    var queued = pending.splice(0);
    queued.forEach(handler);
    emit('viewer_ready', { three_revision: THREE.REVISION });
  }

  boot().catch(function (err) {
    var message = (err && err.message) ? err.message : String(err);
    showError('3D viewer failed to start: ' + message);
    emit('viewer_error', { message: message });
  });
})();
