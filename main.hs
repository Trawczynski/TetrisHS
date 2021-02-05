{-# LANGUAGE OverloadedStrings #-}
import CodeWorld
import System.Random (getStdGen, randomRs)
import Data.Matrix 
import Data.Text (pack)

main:: IO ()
main = do 
  g <- getStdGen
  let figs = randomRs (0, 7) g :: [Int]
  debugActivityOf (initTetris figs) manageEvent drawTetris

type Time = Double
type Tetris = ([Int], Figure, Playfield, Time)
type Figure = ([Point], FigureType)
type FigureType = Char
type Playfield = Matrix Color -- Black -> Empty

initTetris:: [Int] -> Tetris
initTetris figs@(f:rest)
    | f == 0    = initTetris rest
    | otherwise = (figs, generateFigure f, playfield, 0)
      where playfield = matrix 20 10 (\_ -> black)

manageEvent:: Event -> Tetris -> Tetris
manageEvent (TimePassing t) state@(figs,figura,playfield,time) 
                    | time - 1 > 0 = moveDown state
                    | otherwise = (figs,figura,playfield,time+t)
manageEvent (KeyPress t) state@(figs,figura,playfield,time) = newState
                    where newState = case t of 
                                            "Up" -> (figs,rotateFigure figura,playfield,time)
                                            "Down" -> moveDown state
                                            "Left" -> moveLeft state
                                            "Right" -> moveRight state
                                            _ -> state
manageEvent _ state = state

drawTetris:: Tetris -> Picture
drawTetris (_, f, m,_) = ftext & (center $ drawFigure f & drawPlayfield m) & coordinatePlane
  where center = id --translated ((-nc'-1)/2) ((-nr'-1)/2)
        nr' = fromIntegral $ nrows m
        nc' = fromIntegral $ ncols m
        ftext = colored green (lettering $ pack $ show $ fst f) --temp

drawFigure:: Figure -> Picture
drawFigure (ps, t) = pictures $ map (\p -> drawPoint p c) ps
  where c = dull $ case t of
          'O' -> yellow
          'I' -> light blue
          'L' -> orange
          'J' -> blue
          'S' -> red
          'Z' -> green
          'T' -> purple

change :: Matrix a -> (Int,Int) -> (Int,Int)
change m (r,c) = (r',c)
  where r' = (nrows m) - r + 1

drawPlayfield:: Playfield -> Picture
drawPlayfield m = squares & bg
  where nr = nrows m
        nc = ncols m
        squares = pictures [drawPoint p color | 
                            row <- [1..nr], 
                            col <- [1..nc], 
                            let p = (fromIntegral col, fromIntegral row),
                            let color = m !. (row,col),
                            color /= black]
        bg = colored black (translated ((nc'+1)/2) ((nr'+1)/2) (solidRectangle nc' nr'))
          where nc' = fromIntegral nc
                nr' = fromIntegral nr

drawPoint :: Point -> Color -> Picture
drawPoint (x, y) c = colored c (translated x y (solidRectangle 0.95 0.95))

(!.) :: Matrix a -> (Int,Int) -> a
m !. (r,c) = getElem r' c m
  where r' = (nrows m) - r + 1

nextFigure:: [Int] -> (Figure, [Int])
nextFigure (current:next:rest)
  | current /= next && next /= 0 = (generateFigure next, next:rest)
  | otherwise = reroll
    where reroll = (generateFigure next', next':rest')
          (next':rest') = dropWhile (==0) rest

generateFigure:: Int -> Figure
generateFigure n = case n of
  1 -> ([(5,19),(6,19),(5,20),(6,20)], 'O')
  2 -> ([(4,20),(5,20),(6,20),(7,20)], 'I')
  3 -> ([(5,19),(4,19),(6,19),(6,20)], 'L')
  4 -> ([(5,19),(4,19),(6,19),(4,20)], 'J')
  5 -> ([(5,19),(4,19),(5,20),(6,20)], 'S')
  6 -> ([(5,19),(6,19),(4,20),(5,20)], 'Z')
  7 -> ([(5,19),(4,19),(6,19),(5,20)], 'T')
  
-- x : columna en la que se encuentra la figura
-- y : fila en la que se encuentra la figura
validPosition :: [Point] -> Playfield -> Bool
validPosition [] _ = True
validPosition ((x,y):ps) playfield = doesntExceedBoard && doesNotCollide && validPosition ps playfield
                where n = nrows playfield
                      m = ncols playfield
                      doesntExceedBoard = (x >= 1) && (x <= fromIntegral m) && (y >= 1)
                      doesNotCollide = playfield!.(floor y,floor x) == black

moveDown :: Tetris -> Tetris
moveDown state@(figs,figura@(ps,t),playfield,time) 
                | validPosition ps' playfield = (figs,(ps',t),playfield,0)
                | otherwise = (figs',newFig,playfield',0)
                where bajar puntos = case puntos of 
                                        [] -> []
                                        ((n,m):puntos) -> (n,m-1):(bajar puntos)
                      ps' = bajar ps
                      (newFig,figs') = nextFigure figs
                      playfield' = refresh playfield figura

moveLeft :: Tetris -> Tetris
moveLeft state@(figs,figura@(ps,t),playfield,time) 
                | validPosition ps' playfield = (figs,(ps',t),playfield,time)
                | otherwise = state
                where izq puntos = case puntos of 
                                        [] -> []
                                        ((n,m):puntos) -> (n-1,m):(izq puntos)
                      ps' = izq ps
 
moveRight :: Tetris -> Tetris
moveRight state@(figs,figura@(ps,t),playfield,time) 
                | validPosition ps' playfield = (figs,(ps',t),playfield,time)
                | otherwise = state
                where dcha puntos = case puntos of 
                                        [] -> []
                                        ((n,m):puntos) -> (n+1,m):(dcha puntos)
                      ps' = dcha ps

refresh :: Playfield -> Figure -> Playfield
refresh playfield fig@([],_) = playfield
refresh playfield fig@((x,y):ps,t) = refresh (setElem (color t) pos playfield) (ps,t)
                where color _ = red
                      -- el punto (1,4) en el eje de coordenadas corresponde con el (4,1) en la matriz.
                      pos = change playfield (floor y, floor x) 

rotateFigure:: Figure -> Figure
rotateFigure (ps, t) = case t of
  'O' -> (ps, t)
  'I' -> (ps', t)  
    where ps' = rotatePoints center ps
          [_,(x1,y1),(x2,y2),_] = ps
          center  | x1 < x2 = ((x1+x2)/2, y1-0.5)
                  | x1 > x2 = ((x1+x2)/2, y1+0.5)
                  | y1 > y2 = (x1-0.5, (y1+y2)/2)
                  | y1 < y2 = (x1+0.5, (y1+y2)/2)
  t   -> (ps', t)
    where ps' = center:(rotatePoints center rest)
          (center:rest) = ps

rotatePoints:: Point -> [Point] -> [Point]
rotatePoints center ps = map (rotate center) ps
  where rotate (xo,yo) (xi,yi) = (yi-yo+xo, -(xi-xo)+yo)
  