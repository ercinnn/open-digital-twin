/*
 * Open Digital Twin - Three.js scene bridge.
 *
 * Flutter -> Three ("FlutterToThree"):
 *   window.FlutterToThree.receive(json)  (WebViews, via runJavaScript/executeScript)
 *   window.postMessage(json)              (Flutter Web iframe)
 *   json = {"channel":"FlutterToThree","type":<command>,"payload":{...}}
 *   commands: load_model{url}, set_statuses{statuses:{mesh_node_id:status}},
 *             select_node{mesh_node_id|null, focus:bool}, focus_node{mesh_node_id},
 *             reset_camera{}, set_color_mode{mode:"status"|"material"}
 *
 * Three -> Flutter ("ThreeToFlutter"):
 *   json = {"channel":"ThreeToFlutter","type":<event>,"payload":{...}}
 *   events: viewer_ready, model_progress{loaded,total}, model_loaded{mesh_node_ids,url},
 *           model_error{message}, node_selected{mesh_node_id|null}, viewer_error{message}
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
    var selectedId = null;
    var selectionBox = null;
    var homeView = null;
    var cameraTween = null;
    var loadToken = 0;

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
      clearSelectionBox();
    }

    // -------------------------------------------------------------- appearance
    function applyAppearance() {
      nodes.forEach(function (node, id) {
        var status = statuses[id];
        forEachMesh(node, function (mesh) {
          var original = mesh.userData.originalMaterial;
          var mat = mesh.material;
          if (colorMode === 'status' && status && STATUS_COLORS[status] !== undefined) {
            mat.color.setHex(STATUS_COLORS[status]);
            mat.metalness = Math.min(original.metalness !== undefined ? original.metalness : 0, 0.35);
            mat.roughness = 0.55;
          } else {
            mat.color.copy(original.color);
            if (original.metalness !== undefined) mat.metalness = original.metalness;
            if (original.roughness !== undefined) mat.roughness = original.roughness;
          }
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
      if (!node) return;
      selectionBox = new THREE.BoxHelper(node, 0x22d3ee);
      selectionBox.material.depthTest = false;
      selectionBox.material.transparent = true;
      selectionBox.renderOrder = 999;
      scene.add(selectionBox);
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

    function focusNode(id) {
      var node = nodes.get(id);
      if (node) frameBox(new THREE.Box3().setFromObject(node), true);
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
          scene.add(modelRoot);

          var box = new THREE.Box3().setFromObject(modelRoot);
          homeView = box.clone();
          var size = box.getSize(new THREE.Vector3());
          grid.scale.setScalar(Math.max(1, Math.ceil(Math.max(size.x, size.z) * 1.6 / 40)));
          grid.position.set(box.getCenter(new THREE.Vector3()).x, box.min.y - 0.001, box.getCenter(new THREE.Vector3()).z);
          frameBox(box, false);
          applyAppearance();
          updateSelection();
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

    function pick(clientX, clientY) {
      var rect = renderer.domElement.getBoundingClientRect();
      pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
      pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
      raycaster.setFromCamera(pointer, camera);
      var hits = raycaster.intersectObjects(pickables, false);
      return hits.length ? nodeIdFor(hits[0].object) : null;
    }

    renderer.domElement.addEventListener('pointerdown', function (e) { downAt = { x: e.clientX, y: e.clientY }; });
    renderer.domElement.addEventListener('pointerup', function (e) {
      if (!downAt) return;
      var moved = Math.hypot(e.clientX - downAt.x, e.clientY - downAt.y);
      downAt = null;
      if (moved > 5 || e.button !== 0) return;
      selectedId = pick(e.clientX, e.clientY);
      updateSelection();
      emit('node_selected', { mesh_node_id: selectedId });
    });
    renderer.domElement.addEventListener('pointermove', function (e) {
      if (e.buttons) return;
      renderer.domElement.style.cursor = pick(e.clientX, e.clientY) ? 'pointer' : 'default';
    });

    // -------------------------------------------------------------- commands
    handler = function (msg) {
      var p = msg.payload || {};
      switch (msg.type) {
        case 'load_model': loadModel(p.url); break;
        case 'set_statuses': statuses = p.statuses || {}; applyAppearance(); break;
        case 'set_color_mode': colorMode = p.mode === 'material' ? 'material' : 'status'; applyAppearance(); break;
        case 'select_node':
          selectedId = p.mesh_node_id || null;
          updateSelection();
          if (selectedId && p.focus) focusNode(selectedId);
          break;
        case 'focus_node': focusNode(p.mesh_node_id); break;
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

      if (cameraTween) {
        var k = Math.min(1, (performance.now() - cameraTween.start) / cameraTween.duration);
        var e = 1 - Math.pow(1 - k, 3);
        camera.position.lerpVectors(cameraTween.fromPos, cameraTween.toPos, e);
        controls.target.lerpVectors(cameraTween.fromTarget, cameraTween.toTarget, e);
        if (k >= 1) cameraTween = null;
      }

      var pulse = 0.25 + 0.55 * (0.5 + 0.5 * Math.sin(t * 6.0));
      nodes.forEach(function (node, id) {
        var isAlert = statuses[id] === 'alert';
        var isSelected = id === selectedId;
        if (!isAlert && !isSelected) return;
        forEachMesh(node, function (mesh) {
          if (!mesh.material.emissive) return;
          if (isAlert) mesh.material.emissive.setRGB(pulse, 0.02, 0.02);
          else mesh.material.emissive.setRGB(0.02, 0.05, 0.06);
        });
      });
      nodes.forEach(function (node, id) {
        if (statuses[id] === 'alert' || id === selectedId) return;
        forEachMesh(node, function (mesh) {
          if (mesh.material.emissive && mesh.material.emissive.getHex() !== 0) mesh.material.emissive.setHex(0x000000);
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
