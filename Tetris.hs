{-# LANGUAGE OverloadedStrings #-}
module Tetris (runTetris, runCustomTetris) where

import System.Random (getStdGen, randomRs)
import Text.Printf (printf)
import Data.Char (isDigit)
import Data.Text (pack)
import Data.List (nub)
import Data.Matrix
import CodeWorld


-- IO
-- ----------------------------------------------------------------------------------
runTetris :: IO ()
runTetris = do
  fgen <- generateRandoms
  activityOf (startTetris fgen 20 10) manageEvent drawTetris


runCustomTetris :: IO ()
runCustomTetris = do
  rows <- getMinNum "Number of rows" 5
  cols <- getMinNum "Number of columns" 5
  fgen <- generateRandoms

  activityOf (startTetris fgen rows cols) manageEvent drawTetris


generateRandoms :: IO FigureGenerator
generateRandoms = do
  g <- getStdGen
  return $ randomRs (1, 7) g


getMinNum:: String -> Int -> IO Int
getMinNum q minN = do
  putStrLn $ printf "%s (min %d): " q minN
  xs <- getLine

  if all isDigit xs then do
    let n = read xs :: Int

    if n >= minN then
      return n

    else do
      putStrLn $ printf "\t%s is not a valid number (must be %d or highter), please try again." xs minN
      getMinNum q minN
  else do
    putStrLn $ printf "\t%s is not a natural number, please try again." xs
    getMinNum q minN
-- ----------------------------------------------------------------------------------


-- Types
-- ----------------------------------------------------------------------------------
data Tetris =
  Tetris {
    fgen  ::  FigureGenerator,
    f     ::  Figure,
    pf    ::  Playfield,
    t     ::  Time,
    dclk  ::  DefaultClock,
    clk   ::  Clock,
    sc    ::  Score,
    st    ::  State
  }

type FigureGenerator = [Int]
type Figure = ([Point], FigureType)
type FigureType = Char
type Playfield = Matrix Color
type Time = Double
type DefaultClock = Double
type Clock = Double
type Score = Int
data State = Start | Normal | Pause | GameOver

data Direction = L | R
-- ----------------------------------------------------------------------------------


-- Init
-- ----------------------------------------------------------------------------------
startTetris :: FigureGenerator -> Int -> Int -> Tetris
startTetris fgen nr nc = tetris {st = Start}
  where tetris = initTetris fgen nr nc

initTetris :: FigureGenerator -> Int -> Int -> Tetris
initTetris fgen@(n:rest) nr nc = Tetris fgen f pf 0 1 1 0 Normal
    where pf = matrix nr nc (\_ -> black)
          f = generateFigure n pf

newGame:: Tetris -> Tetris
newGame tetris = initTetris fgen' (nrows pf_) (ncols pf_)
  where fgen' = drop 3 (fgen tetris)
        pf_ = pf tetris
-- ----------------------------------------------------------------------------------


-- Events
-- ----------------------------------------------------------------------------------
manageEvent, manageStart, manageNormal, managePause, manageGameover::
  Event -> Tetris -> Tetris

manageEvent event tetris = manager event tetris
  where manager = case st tetris of
                    Start     -> manageStart
                    Normal    -> manageNormal
                    Pause     -> managePause
                    GameOver  -> manageGameover

manageStart (KeyRelease _) tetris = tetris {st = Normal}
manageStart _ tetris = tetris

manageNormal (TimePassing dt) tetris
  | clk tetris < 0  = moveDown tetris
  | otherwise       = tetris {t = (t tetris)+dt, clk = (clk tetris)-dt}
manageNormal (KeyRelease k) tetris = case k of
  "Esc" -> tetris {st = Pause}
  "C"   -> instantDown tetris
  _     -> tetris
manageNormal (KeyPress k) tetris = case k of
  "Up"    -> tryRotateFigureRight tetris
  "Z"     -> tryRotateFigureLeft tetris
  "Down"  -> moveDown tetris
  "Left"  -> moveLeft tetris
  "Right" -> moveRight tetris
  _       -> tetris
manageNormal _ tetris = tetris

managePause (KeyRelease "Esc") tetris = tetris {st = Normal}
managePause (KeyRelease "N") tetris = newGame tetris
managePause _ tetris = tetris

manageGameover (KeyRelease "N") tetris = newGame tetris
manageGameover _ tetris = tetris
-- ----------------------------------------------------------------------------------


-- Drawing
-- ----------------------------------------------------------------------------------
screenWidth, screenHeight :: Double
screenWidth = 42
screenHeight = 20

drawTetris :: Tetris -> Picture
drawTetris tetris = draw tetris & bg
  where bg = solidRectangle screenWidth screenHeight
        draw = case st tetris of
                Start     -> drawStart
                Normal    -> drawNormal
                Pause     -> drawPause
                GameOver  -> drawGameOver

-- Start
drawStart :: Tetris -> Picture
drawStart tetris = drawTextLines ls
  where ls = ["Press any key",
              "to start"]

-- Normal
drawNormal :: Tetris -> Picture
drawNormal tetris = scale.center $ ps
  where ps = pictures [ drawFigure (f tetris) pf_, 
                        drawPlayfield pf_, 
                        drawStats tetris]
        scale = dilated $ 0.75 * (min (screenWidth/nc') (screenHeight/nr'))
        center = translated ((-nc'-1)/2) ((-nr'-1)/2)
        nr' = fromIntegral $ nrows $ pf_
        nc' = fromIntegral $ ncols $ pf_
        pf_ = pf tetris

drawFigure :: Figure -> Playfield -> Picture
drawFigure f@(ps, ft) pf = draw ps c & draw sps (translucent c)
  where c = figuretypeColor ft
        (sps, _) = obtainMaxDown f pf
        draw ps c = pictures $ foldr f [] ps
          where nr' = fromIntegral $ nrows pf
                f (x,y) ac  | y <= nr'  = (drawSquare (x,y) c):ac
                            | otherwise = ac

drawPlayfield :: Playfield -> Picture
drawPlayfield pf = pictures [if c /= black then drawSquare p c else drawPoint p |
                            row <- [1..nrows pf],
                            col <- [1..ncols pf],
                            let p = (fromIntegral col, fromIntegral row),
                            let c = pf !. p]

drawSquare :: Point -> Color -> Picture
drawSquare (x, y) c = colored c (translated x y (solidRectangle 0.95 0.95))

drawPoint :: Point -> Picture
drawPoint (x, y) = colored pointColor (translated x y (solidRectangle 0.1 0.1))

drawStats :: Tetris -> Picture
drawStats tetris =  moveY 1.5 (scaleText (stringPic "Score"))       & moveY 1.1 (scaleData (stringPic score))  &
                    moveY 2.5 (scaleText (stringPic "Time played")) & moveY 2.1 (scaleData (stringPic time))   &
                    moveY 3.5 (scaleText (stringPic "Bonus"))       & moveY 3.1 (scaleData (stringPic bonus))  &
                    moveY 6.5 (scaleText (stringPic "Pause"))       & moveY 6.1 (scaleData (stringPic "ESC"))  &
                    moveY 8.5 (scaleData $ drawNextFigure fig)
  where moveY y = translated (-1*k) (y*k) where k = nr'/10
        scaleText = dilated $ nr' * 0.0225
        scaleData = dilated $ nr' * 0.04
        score = formatScore $ sc tetris
        time = formatTime $ t tetris
        bonus = formatBonus $ dclk tetris
        nr' = fromIntegral $ nrows $ pf tetris
        fig = centerAxis $ spawnFigure (typ)
          where typ = fst $ nextFgen (fgen tetris)

drawNextFigure :: Figure -> Picture
drawNextFigure (ps, ft) = colored green (pictures $ map (\p -> draw p) ps)
  where draw (x,y) = translated x y (thickRectangle 0.11 0.82 0.82)

centerAxis :: Figure -> Figure
centerAxis (ps, ft) = (ps', ft)
  where ps' | ft == 'O' || ft == 'I' = map (\(x,y) -> (x-0.5,y)) ps
            | otherwise = ps

-- Pause
drawPause :: Tetris -> Picture
drawPause tetris = drawTitle "PAUSED" & drawControl

drawControl:: Picture
drawControl = drawTextLines ls
  where ls = ["Esc - Resume",
              "N - New game",
              "C - Hard drop",
              "Z - Rotate left",
              "Up arrow - Rotate right",
              "Left arrow - Move left",
              "Right arrow - Move right",
              "Down arrow - Move down"]

-- GameOver
drawGameOver :: Tetris -> Picture
drawGameOver tetris = drawTitle "GAME OVER" & translated 0 (-1.5) text
  where text = drawTextLines ["Score",
                              show $ sc tetris,
                              "",
                              "Time played",
                              formatTime $ t tetris,
                              "", "",
                              "Press N to",
                              "start a new game"]
        
-- Generic functions
drawTitle :: String -> Picture
drawTitle title = translate.scale $ stringPic title
  where translate = translated 0 6
        scale = dilated 3

drawTextLines:: [String] -> Picture
drawTextLines ls = pictures [translated 0 y (stringPic l) | (l, y) <- zip ls [n, n-1..]]
  where n = (fromIntegral $ length ls)/2 - 0.5

stringPic:: String -> Picture
stringPic = (colored green).(styledLettering Plain Monospace).pack
-- ----------------------------------------------------------------------------------


-- Color & format
-- ----------------------------------------------------------------------------------
figuretypeColor :: FigureType -> Color
figuretypeColor ft = dull $ case ft of
  'O' -> yellow
  'I' -> light blue
  'L' -> orange
  'J' -> blue
  'S' -> red
  'Z' -> green
  'T' -> purple

pointColor:: Color
pointColor = bright yellow

formatScore:: Score -> String
formatScore = printf "%05d"

formatTime:: Time -> String
formatTime t = printf "%02d:%02d" m s
  where (m, s) = divMod (floor t) 60 :: (Int, Int)

formatBonus:: DefaultClock -> String
formatBonus dclk = printf "x%.2f" (1/dclk)
-- ----------------------------------------------------------------------------------


-- Playfield
-- ----------------------------------------------------------------------------------
(!.) :: Playfield -> Point -> Color
pf !. (x,y) = getElem r c pf
  where r = (nrows pf) - (round y) + 1
        c = round x

setElem' :: Color -> Point -> Playfield -> Playfield
setElem' color (x,y) pf = setElem color (r,c) pf
  where r = (nrows pf) - (round y) + 1
        c = round x

validPosition :: Figure -> Playfield -> Bool
validPosition ([], _) _ = True
validPosition ((x,y):ps, ft) pf = doesNotExceed && doesNotCollide && validPosition (ps, ft) pf
  where doesNotCollide = y > nr' || pf !. (x,y) == black
        doesNotExceed = x >= 1 && x <= nc' && y >= 1
        nr' = fromIntegral $ nrows pf
        nc' = fromIntegral $ ncols pf

updatePlayfield :: Playfield -> Figure -> (Playfield, [Int])
updatePlayfield pf ([], _)    = removeFullRows pf
updatePlayfield pf (p:ps, ft) = updatePlayfield pf' (ps, ft)
  where pf' = setElem' c p pf
        c = figuretypeColor ft

removeFullRows :: Playfield -> (Playfield, [Int])
removeFullRows pf
  | null is   = (pf,[])
  | otherwise = (newRows toAdd nc <-> removeRows is pf, is)
  where is = fullRows pf -- lista de las filas a eliminar
        toAdd = length is
        nc = ncols pf

-- las líneas a introducir arriba de pf si procede. Serán tantas como eliminadas.
newRows :: Int -> Int -> Playfield
newRows nr nc = matrix nr nc (\_ -> black)

-- fullRows es la función encargada de obtener una lista de índices con las filas a borrar.
fullRows :: Playfield -> [Int]
fullRows pf = [ row |
                (row, colors) <- zip [1..] (toLists pf),
                all (/= black) colors]

removeRows :: [Int] -> Playfield -> Playfield
removeRows [] pf = pf
removeRows toRemove pf = fromLists [row | (i,row) <- zip [1..nr] pfList, notElem i toRemove]
  where nr = nrows pf
        pfList = toLists pf

moveDown :: Tetris -> Tetris
moveDown tetris
  | validPosition mf pf_  = tetris {f = mf, clk = dclk tetris}
  | isGameOver f_ pf_     = tetris {st = GameOver}
  | otherwise             = placeFigure tetris
  where mf = moveFigure f_ 0 (-1)
        pf_ = pf tetris
        f_ = f tetris

instantDown :: Tetris -> Tetris
instantDown tetris
  | isGameOver f' pf_ = tetris {st = GameOver}
  | otherwise         = placeFigure $ tetris {f = f'}
  where f' = obtainMaxDown (f tetris) pf_
        pf_ = pf tetris

placeFigure :: Tetris -> Tetris
placeFigure tetris = tetris {fgen = fgen', f = nf, pf = pf', dclk = dclk', clk = dclk', sc = sc'}
  where pf_ = pf tetris
        dclk_ = dclk tetris
        (nf, fgen') = nextFigure (fgen tetris) pf_
        (pf', delRows) = updatePlayfield pf_ (f tetris)
        dclk' = max 0.15 (dclk_-0.01)
        sc' = (sc tetris) + (round $ n * 100 * (1/dclk_))
          where n = fromIntegral $ length $ delRows

isGameOver:: Figure -> Playfield -> Bool
isGameOver (ps, _) pf = any (>ceil) (map snd ps)
  where ceil = fromIntegral $ nrows pf

moveLeft :: Tetris -> Tetris
moveLeft tetris
  | validPosition mf (pf tetris) = tetris {f = mf}
  | otherwise = tetris
  where mf = moveFigure (f tetris) (-1) 0

moveRight :: Tetris -> Tetris
moveRight tetris
  | validPosition mf (pf tetris) = tetris {f = mf}
  | otherwise = tetris
  where mf = moveFigure (f tetris) 1 0

moveFigure :: Figure -> Double -> Double -> Figure
moveFigure (ps, ft) dx dy = (move ps, ft)
  where move [] = []
        move ((x,y):r) = (x+dx, y+dy):(move r)
-- ----------------------------------------------------------------------------------


-- Figure
-- ----------------------------------------------------------------------------------
nextFigure :: FigureGenerator -> Playfield -> (Figure, FigureGenerator)
nextFigure fgen pf = (generateFigure n pf, fgen')
  where (n, fgen') = nextFgen fgen

nextFgen :: FigureGenerator -> (Int, FigureGenerator)
nextFgen (current:next:next2:rest)
  | current /= next = (next, next:rest)
  | otherwise       = (next2, next2:rest)

generateFigure :: Int -> Playfield -> Figure
generateFigure n pf = (ps', ft)
  where ps' = map (\(x, y) -> (x+dx, y+dy)) ps
        (ps, ft) = spawnFigure n
        dx  | even nc                 = nc'/2
            | ft == 'I' || ft == 'O'  = nc'/2 - 0.5
            | otherwise               = nc'/2 + 0.5
        dy = nr' + 1
        nc = ncols pf
        nc' = fromIntegral nc
        nr' = fromIntegral $ nrows pf

equivalent :: Char -> Int
equivalent c = case c of  'O' -> 1
                          'I' -> 2
                          'L' -> 3
                          'J' -> 4
                          'S' -> 5
                          'Z' -> 6
                          'T' -> 7

spawnFigure :: Int -> Figure
spawnFigure n = case n of
  1 -> ([(0,1),   (1,1),    (0,2),    (1,2)],   'O')
  2 -> ([(-1,1),  (0,1),    (1,1),    (2,1)],   'I')
  3 -> ([(0,1),   (-1,1),   (1,1),    (1,2)],   'L')
  4 -> ([(0,1),   (-1,1),   (1,1),    (-1,2)],  'J')
  5 -> ([(0,1),   (-1,1),   (0,2),    (1,2)],   'S')
  6 -> ([(0,1),   (1,1),    (-1,2),   (0,2)],   'Z')
  7 -> ([(0,1),   (-1,1),   (1,1),    (0,2)],   'T')

tryRotateFigureRight, tryRotateFigureLeft :: Tetris -> Tetris
tryRotateFigureRight tetris = tryRotateFigure tetris R
tryRotateFigureLeft tetris = tryRotateFigure tetris L

tryRotateFigure :: Tetris -> Direction -> Tetris
tryRotateFigure tetris dir = case maybef' of
  Nothing -> tetris
  Just f' -> tetris {f = f'}
  where maybef' = safeHead $ filter (\f -> validPosition f (pf tetris)) (map ($rf) mvs)
        rf = rotateFigure (f tetris) dir
        mvs = [ \x -> moveFigure x 0    0,
                \x -> moveFigure x 1    0,
                \x -> moveFigure x (-1) 0,
                \x -> moveFigure x 2    0,
                \x -> moveFigure x (-2) 0]

rotateFigure :: Figure -> Direction -> Figure
rotateFigure (ps, ft) dir = case ft of
  'O' -> (ps, ft)
  'I' -> (ps', ft)
    where ps' = rotatePoints center ps dir
          [_,(x1,y1),(x2,y2),_] = ps
          center  | x1 < x2 = ((x1+x2)/2, y1-0.5)
                  | x1 > x2 = ((x1+x2)/2, y1+0.5)
                  | y1 > y2 = (x1-0.5, (y1+y2)/2)
                  | y1 < y2 = (x1+0.5, (y1+y2)/2)
  ft   -> (ps', ft)
    where ps' = center:(rotatePoints center rest dir)
          (center:rest) = ps

rotatePoints :: Point -> [Point] -> Direction -> [Point]
rotatePoints center ps dir = map (rotate center) ps
  where rotate (xo,yo) (xi,yi) = case dir of
          R -> (yi-yo+xo, -(xi-xo)+yo)
          L -> (-(yi-yo)+xo, xi-xo+yo)

-- en caso de no haber ninguna ficha parada abajo m será 0 -> ¿Por qué 0 y no 1? que m fuera 1 significaría que hay
-- una ficha en la fila uno, entonces la sombra se ubicaría en la fila 2 -> df = y - 1. ys = y - (y-1) + 1 = 2.
obtainMaxDown :: Figure -> Playfield -> Figure
obtainMaxDown (ps,t) pf = (sps,t)
  where sps = map (\(x,y) -> (x, y-yDif+1)) ps
        yDif = minimum [y - maxNotEmptyRow | 
                        (x,y) <- ps, 
                        let ys2 = [ y2 | 
                                    y2 <- [y, y-1..1],
                                    y2 <= nr',
                                    pf !. (x,y2) /= black],
                        let maxNotEmptyRow = if null ys2 then 0 else head ys2]
        nr' = fromIntegral $ nrows pf
-- ----------------------------------------------------------------------------------


-- Utils
-- ----------------------------------------------------------------------------------
safeHead:: [a] -> Maybe a
safeHead [] = Nothing
safeHead l = Just $ head l
-- ----------------------------------------------------------------------------------
