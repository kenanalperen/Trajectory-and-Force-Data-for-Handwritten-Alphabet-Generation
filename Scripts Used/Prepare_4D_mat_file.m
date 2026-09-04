% ==========================================================================
%  Prepare_4D_mat_file.m
%  Converts raw CSV experiment data into a 4D .mat file for Robot_Learning_Code.m
%
%  Key difference from Prepare_mat_file.m:
%    - Resampling is done UNIFORMLY IN ARC-LENGTH (not time-normalised).
%      This means each of the nbSamples points is spaced equally along the
%      spatial path.  Fast regions produce large spatial jumps per sample;
%      slow regions produce small spatial jumps per sample.
%    - Real elapsed time is stored as a 4th row in pos/vel/acc, normalised
%      to [0, 1] over the full trajectory duration.
%      vel(4,:) = d(t_norm)/d(arc_step)  ∝  1/speed  (large = slow, small = fast)
%      This lets the GMM+GMR learn the full motion dynamics including speed.
%
%  Output format:
%    demos{n}.pos  -- 4 x nbSamples  [x_mm; y_mm; force_N; t_norm]
%    demos{n}.vel  -- 4 x nbSamples  (derivatives w.r.t. arc-length step)
%    demos{n}.acc  -- 4 x nbSamples
%    avg_duration  -- scalar (mean real duration of selected demos, in seconds)
%                     Used by Robot_Learning_Code.m to convert t_norm → seconds.
%
%  Output file: <CHAR>_<Case>_4D.mat  (e.g. B_Uppercase_4D.mat)
% ==========================================================================

clearvars; clc; close all;

% ── Dock all figures ───────────────────────────────────────────────────────
set(0, 'DefaultFigureWindowStyle', 'docked');

% ==========================================================================
%  USER SETTINGS
% ==========================================================================

TARGET_CHARACTER = 'Z';           % Single letter, e.g. 'G', 'B', 'E'
TARGET_CASE      = 'Lowercase';   % 'Uppercase' or 'Lowercase'
nbDemos          = 21;            % Number of demonstrations to select
nbSamples        = 200;           % Arc-length samples per demonstration
CSV_FOLDER       = 'Experiment_Character_Data_csv';

% Pen-lift detection (gap in x,y AND low force at next point)
dist_thresh  = 5.0;    % mm  — Euclidean jump threshold
force_thresh = 0.75;   % N   — force at next point below this → pen lift

% ==========================================================================
%  LOAD CSV
% ==========================================================================

charField = [TARGET_CHARACTER '_' TARGET_CASE];
csvFile   = fullfile(CSV_FOLDER, [charField '.csv']);
if ~isfile(csvFile)
    csvFile = fullfile(CSV_FOLDER, [lower(TARGET_CHARACTER) '_' TARGET_CASE '.csv']);
end
if ~isfile(csvFile)
    error('CSV not found for %s.\nLooked in: %s', charField, CSV_FOLDER);
end

fprintf('Loading: %s\n', csvFile);
T = readtable(csvFile, 'TextType', 'string');
fprintf('  %d rows loaded.\n\n', height(T));

% ==========================================================================
%  POOL ALL (PARTICIPANT, REPETITION) ENTRIES
% ==========================================================================

pNums    = unique(T.participant);
allEntries = struct('label',{}, 'duration',{}, 'x',{}, 'y',{}, 't',{}, 'f',{});
entryIdx = 0;

for pi = 1:numel(pNums)
    pNum  = pNums(pi);
    pMask = T.participant == pNum;
    rNums = unique(T.repetition(pMask));
    for ri = 1:numel(rNums)
        rNum  = rNums(ri);
        rMask = pMask & (T.repetition == rNum);
        t_raw = double(T.time(rMask));
        t_raw = t_raw - min(t_raw);
        entryIdx = entryIdx + 1;
        allEntries(entryIdx).label    = sprintf('P%d_rep%d', pNum, rNum);
        allEntries(entryIdx).duration = max(t_raw);
        allEntries(entryIdx).x        = double(T.x_mm(rMask));
        allEntries(entryIdx).y        = double(T.y_mm(rMask));
        allEntries(entryIdx).t        = t_raw;
        allEntries(entryIdx).f        = double(T.force_N(rMask));
    end
end

fprintf('Total available entries: %d\n', entryIdx);
if entryIdx < nbDemos
    error('Requested %d demos but only %d available.', nbDemos, entryIdx);
end

% ==========================================================================
%  PROCESS EACH ENTRY — ARC-LENGTH RESAMPLING + TIME AS 4TH DIMENSION
%  (with error catching: skip entries that cause interpolation errors)
% ==========================================================================

fprintf('\nProcessing entries (arc-length resampling)...\n');
processedEntries = {};          % cell array of successfully processed entries

for e = 1:entryIdx
    try
        x_raw = allEntries(e).x(:)';    % row vectors
        y_raw = allEntries(e).y(:)';
        t_raw = allEntries(e).t(:)';
        f_raw = allEntries(e).f(:)';
        total_dur = allEntries(e).duration;

        % ----- detect pen-lift jumps -----
        nRaw   = numel(x_raw);
        isJump = false(1, nRaw-1);
        for i = 1:nRaw-1
            d = sqrt((x_raw(i+1)-x_raw(i))^2 + (y_raw(i+1)-y_raw(i))^2);
            if d > dist_thresh && f_raw(i+1) < force_thresh
                isJump(i) = true;
            end
        end

        % ----- split into segments -----
        segIdx = cumsum([1, isJump]);
        nSeg   = max(segIdx);

        % Allocate nbSamples proportionally to arc-length of each segment
        seg_arclen = zeros(1, nSeg);
        for s = 1:nSeg
            idx = find(segIdx == s);
            x_pts = x_raw(idx);
            y_pts = y_raw(idx);
            f_pts = f_raw(idx);
            t_pts = t_raw(idx);

            % ---------- remove consecutive duplicate positions ----------
            keep = [true, diff(x_pts).^2 + diff(y_pts).^2 > 1e-12];
            x_pts = x_pts(keep);
            y_pts = y_pts(keep);
            f_pts = f_pts(keep);
            t_pts = t_pts(keep);
            if length(x_pts) < 2
                x_pts = [x_pts, x_pts];
                y_pts = [y_pts, y_pts];
                f_pts = [f_pts, f_pts];
                t_pts = [t_pts, t_pts];
            end

            dx = diff(x_pts);  dy = diff(y_pts);
            ds = sqrt(dx.^2 + dy.^2);
            seg_arclen(s) = max(sum(ds), eps);   % avoid zero length
        end
        total_arclen = sum(seg_arclen);

        seg_samples = max(2, round(seg_arclen / total_arclen * nbSamples));
        % Adjust to exactly nbSamples
        delta = nbSamples - sum(seg_samples);
        if delta ~= 0
            [~, maxS] = max(seg_samples);
            seg_samples(maxS) = seg_samples(maxS) + delta;
        end

        % ----- resample each segment uniformly in arc-length -----
        x_all  = zeros(1, nbSamples);
        y_all  = zeros(1, nbSamples);
        f_all  = zeros(1, nbSamples);
        t_all  = zeros(1, nbSamples);   % real time at each arc-length sample

        sample_start = 1;
        for s = 1:nSeg
            idx = find(segIdx == s);
            x_pts = x_raw(idx);
            y_pts = y_raw(idx);
            f_pts = f_raw(idx);
            t_pts = t_raw(idx);

            % Apply the same duplicate removal to the interpolation data
            keep = [true, diff(x_pts).^2 + diff(y_pts).^2 > 1e-12];
            x_pts = x_pts(keep);
            y_pts = y_pts(keep);
            f_pts = f_pts(keep);
            t_pts = t_pts(keep);
            if length(x_pts) < 2
                x_pts = [x_pts, x_pts];
                y_pts = [y_pts, y_pts];
                f_pts = [f_pts, f_pts];
                t_pts = [t_pts, t_pts];
            end

            n_target = seg_samples(s);

            % Cumulative arc-length within this segment
            dx_s  = diff(x_pts);  dy_s = diff(y_pts);
            ds_s  = sqrt(dx_s.^2 + dy_s.^2);
            s_cum = [0, cumsum(ds_s)];
            s_cum_norm = s_cum / max(s_cum(end), eps);   % 0..1

            % Ensure s_cum_norm is strictly increasing (fix floating-point duplicates)
            [s_cum_norm, uniqIdx] = unique(s_cum_norm, 'stable');
            x_pts = x_pts(uniqIdx);
            y_pts = y_pts(uniqIdx);
            f_pts = f_pts(uniqIdx);
            t_pts = t_pts(uniqIdx);
            if length(x_pts) < 2
                x_pts = [x_pts, x_pts];
                y_pts = [y_pts, y_pts];
                f_pts = [f_pts, f_pts];
                t_pts = [t_pts, t_pts];
                s_cum_norm = [0, 1];
            end

            % Uniform query in arc-length
            s_query = linspace(0, 1, n_target);

            x_all(sample_start : sample_start+n_target-1) = interp1(s_cum_norm, x_pts, s_query, 'pchip');
            y_all(sample_start : sample_start+n_target-1) = interp1(s_cum_norm, y_pts, s_query, 'pchip');
            f_all(sample_start : sample_start+n_target-1) = interp1(s_cum_norm, f_pts, s_query, 'pchip');
            t_all(sample_start : sample_start+n_target-1) = interp1(s_cum_norm, t_pts, s_query, 'pchip');

            sample_start = sample_start + n_target;
        end

        % ----- normalise time to [0, 1] -----
        t_norm = t_all / max(t_all(end), eps);   % 0..1 (monotone, encodes speed)

        pos = [x_all; y_all; f_all; t_norm];    % 4 x nbSamples

        % ----- compute derivatives w.r.t. arc-length step -----
        ds_step = total_arclen / (nbSamples - 1);

        vel = zeros(4, nbSamples);
        acc = zeros(4, nbSamples);
        for row = 1:4
            vel(row,:) = gradient(pos(row,:)) / ds_step;
            acc(row,:) = gradient(vel(row,:)) / ds_step;
        end

        % Store successful entry
        processedEntries{end+1}.label    = allEntries(e).label;
        processedEntries{end}.duration   = total_dur;
        processedEntries{end}.pos        = pos;
        processedEntries{end}.vel        = vel;
        processedEntries{end}.acc        = acc;

    catch ME
        % If any error occurs during processing of this entry, skip it
        fprintf('  [WARNING] Skipping entry %s due to error: %s\n', ...
                allEntries(e).label, ME.message);
    end
end

nValid = numel(processedEntries);
fprintf('\nSuccessfully processed entries: %d\n', nValid);

if nValid < nbDemos
    fprintf('  Not enough valid entries (%d) to select %d demos.\n', nValid, nbDemos);
    nbDemos = nValid;
    fprintf('  Reducing nbDemos to %d.\n', nbDemos);
    if nbDemos == 0
        error('No valid entries remain. Check your data or adjust threshold settings.');
    end
end

% ==========================================================================
%  SELECT nbDemos ENTRIES BY PAIRWISE SIMILARITY (position + force + time)
% ==========================================================================

fprintf('\nComputing pairwise distances for selection...\n');

nTotal  = nValid;
pos_all = cellfun(@(e) e.pos, processedEntries, 'UniformOutput', false);
pos_mat = cat(3, pos_all{:});   % 4 x nbSamples x nTotal

D = zeros(nTotal, nTotal);
for i = 1:nTotal
    for j = i+1:nTotal
        xy_diff = pos_mat(1:2,:,i) - pos_mat(1:2,:,j);
        f_diff  = pos_mat(3,:,i) - pos_mat(3,:,j);
        t_diff  = pos_mat(4,:,i) - pos_mat(4,:,j);   % t_norm diff
        d_xy    = sqrt(sum(xy_diff.^2, 1));
        d_f     = 30  * abs(f_diff);
        d_t     = 30  * abs(t_diff);   % time weight (user spec: ×10)
        D(i,j)  = sum(d_xy + d_f + d_t);
        D(j,i)  = D(i,j);
    end
end

totalDist   = sum(D, 2);
[~,sortIdx] = sort(totalDist);
selectedIdx = sortIdx(1:nbDemos);

fprintf('Selected %d demonstrations (most similar in x,y,force,time):\n', nbDemos);
for k = 1:nbDemos
    idx = selectedIdx(k);
    fprintf('  [%2d]  %-15s  duration = %.3f s\n', k, ...
            processedEntries{idx}.label, processedEntries{idx}.duration);
end

% Compute and save average duration of selected demos
selectedDurs = arrayfun(@(k) processedEntries{selectedIdx(k)}.duration, 1:nbDemos);
avg_duration = mean(selectedDurs);
fprintf('\nAverage duration of selected demos: %.4f s\n', avg_duration);

% ==========================================================================
%  BUILD DEMOS STRUCT AND SAVE
% ==========================================================================

demos = cell(1, nbDemos);
for k = 1:nbDemos
    e = processedEntries{selectedIdx(k)};
    demos{k}.pos = e.pos;
    demos{k}.vel = e.vel;
    demos{k}.acc = e.acc;
end

outFile = sprintf('%s_%s_4D.mat', TARGET_CHARACTER, TARGET_CASE);
save(outFile, 'demos', 'avg_duration');
fprintf('Saved: %s  (%d demos, pos/vel/acc = 4×%d, avg_dur=%.4fs)\n', ...
        outFile, nbDemos, nbSamples, avg_duration);

% ==========================================================================
%  SANITY PLOT — all selected demos (x,y coloured by force)
% ==========================================================================

% cmap = blueRedCmap(256);
% figure('Name', sprintf('%s — %d selected 4D demos', charField, nbDemos), 'Color','w');
% 
% for k = 1:nbDemos
%     f_vals = demos{k}.pos(3,:);
%     fNorm  = (f_vals - min(f_vals)) / (max(f_vals) - min(f_vals) + eps);
%     cIdx   = max(1, round(fNorm * 255) + 1);
%     cols   = cmap(cIdx, :);
% 
%     subplot(3, ceil(nbDemos/3), k);
%     scatter(demos{k}.pos(1,:), demos{k}.pos(2,:), 10, cols, 'filled', ...
%             'MarkerEdgeColor','none');
%     title(sprintf('Demo %d', k), 'FontSize', 8);
%     axis equal; axis tight;
%     set(gca, 'XTick',[], 'YTick',[]);
% end
% sgtitle(sprintf('%s — %d 4D demos (colour = force)', strrep(charField,'_',' '), nbDemos));
% colormap(cmap);

% ==========================================================================
%  HELPER FUNCTIONS
% ==========================================================================

function cmap = blueRedCmap(n)
    if nargin < 1, n = 256; end
    keys = [0 0 1; 0 0.5 1; 0 1 1; 0.5 1 0.5; 1 1 0; 1 0.5 0; 1 0 0];
    xi   = linspace(0, 1, size(keys,1));
    xq   = linspace(0, 1, n);
    cmap = min(max(interp1(xi, keys, xq, 'pchip'), 0), 1);
end